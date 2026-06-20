# GKE Spot vs On-Demand Capacity Ratio Analysis

This document provides a detailed analysis of our GKE multi-nodepool scaling design, discussing how the 80% Spot / 20% On-Demand compute ratio is maintained under normal conditions, and the edge cases where the ratio will break.

---

## 1. Design Architecture

To split workloads between Spot and On-Demand compute resources, the design uses standard Kubernetes components:
*   **Infrastructure**: Two GKE Node Pools with autoscaling enabled:
    *   `spot-pool` (Spot VMs, autoscaling 0 to 10 nodes, labeled `capacity-type=spot`, tainted `cloud.google.com/gke-spot=true:NoSchedule`).
    *   `on-demand-pool` (On-Demand VMs, autoscaling 1 to 5 nodes, labeled `capacity-type=on-demand`).
*   **Workloads**: Two separate Deployments targeting the respective node pools:
    *   `ratio-app-spot` (starts at 8 replicas, tolerates spot taint, selects `capacity-type=spot`).
    *   `ratio-app-ondemand` (starts at 2 replicas, selects `capacity-type=on-demand`).
    *   *Both deployments share the label `app: ratio-app` in their pod templates.*
*   **Service Routing**: A single ClusterIP Service (`ratio-app-service`) selecting `app: ratio-app`.
*   **Autoscaling**: Two HPAs targeting their respective deployments, both configured with a **50% CPU utilization target**:
    *   Spot HPA: `minReplicas: 8`, `maxReplicas: 80`
    *   On-Demand HPA: `minReplicas: 2`, `maxReplicas: 20`

---

## 2. Ratio Maintenance (Normal Conditions)

Under normal operating conditions where GCP has sufficient capacity for both Spot and On-Demand VMs, the 80/20 ratio is maintained through the following mechanism:

1.  **Equal Traffic Load per Pod**: The Service load-balances incoming traffic evenly across all pods sharing the `app: ratio-app` label. Because traffic is split evenly, every active pod across both deployments experiences roughly the same CPU utilization.
2.  **Identical Scaling Multiplier**: Because average CPU per pod is the same for both deployments, both HPAs calculate the same scaling ratio:
    $$\text{ScaleFactor} = \frac{\text{CurrentAverageCPU}}{\text{TargetCPU (50\%)}}$$
3.  **Proportional Scaling**: Both HPAs multiply their current replicas by this same factor. Because we set the min/max replica boundaries to be proportional (8/80 for Spot, 2/20 for On-Demand), they scale up and down in sync, preserving the 4:1 (80/20) ratio.
4.  **Autoscaling Alignment**: As pod replicas scale up proportionally, they create resource requests on their respective nodepools. GKE Cluster Autoscaler provisions nodes in each pool to fit the pending pods, aligning the physical node count to the desired ratio.

---

## 3. Scenarios Where the Ratio Breaks

While simple and elegant, this design **does not guarantee** the 80/20 ratio under all circumstances. There are critical scenarios where the ratio will break.

### Scenario A: Spot VM Stockout (The Critical Failure Case)
If Google Cloud runs out of Spot VM capacity in the zone (stockout), the `spot-pool` cannot scale up. 
1.  **Pending Pods with 0% Metric**: The Spot HPA scales up desired replicas to (for example) 40. GKE fails to provision nodes, so 8 pods are running (on existing nodes) and 32 pods stay in `Pending`.
2.  **HPA Dampening Effect**: To prevent aggressive scale-ups when pods are failing to start, the Kubernetes HPA algorithm assumes `Pending` pods are consuming **0% CPU** of the target metric.
3.  **Calculated CPU Drops**: The Spot HPA calculates the average CPU as:
    $$\text{AverageCPU} = \frac{(8 \text{ running pods} \times 80\% \text{ CPU}) + (32 \text{ pending pods} \times 0\% \text{ CPU})}{40 \text{ desired pods}} = 16\%$$
4.  **Scale-Up Halts & Reverses**: Because 16% CPU is far below the 50% target, the Spot HPA **stops scaling up** and instead scales down its desired count (e.g., back to 13).
5.  **On-Demand Continues to Scale**: Meanwhile, the On-Demand pool has no stockout. Its HPA sees 80% CPU on all running pods and successfully scales up to 16.
6.  **Broken Ratio & No Auto-Recovery**: The ratio is skewed (13 Spot desired / 16 On-Demand desired). Because the Spot HPA scaled down its *desired* count, the Spot pool is no longer requesting 40 pods. Even if GCP capacity returns later, the cluster **will not automatically recover the 80/20 ratio** because the Spot HPA has locked itself into a lower desired state.

### Scenario B: Autoscaler Warm-Up Lag (Transient Skew)
When scaling up rapidly, if one nodepool provisions VMs faster than the other:
*   One set of pods will transition to `Running` sooner.
*   This causes a transient skew in the **running** pod and node ratio (e.g. 90% Spot / 10% On-Demand).
*   *Note: This is a temporary skew. Once the slower nodepool finishes provisioning, the ratio automatically recovers to 80/20 because the desired counts in the HPAs were not modified.*

---

## 4. Production Recommendations

Depending on your business requirements, you should choose one of two approaches:

### Approach 1: Prioritize Service Availability (Current Design)
If it is more important to keep the application running than to maintain a strict cost ratio:
*   The current dual-HPA design is appropriate.
*   During a Spot stockout, the On-Demand deployment will scale up to handle the load while the Spot deployment is stuck. This acts as a **graceful fallback** to save the service, at the cost of higher cloud spend.

### Approach 2: Prioritize Strict Cost Ratio (Guaranteed Ratio)
If you must strictly limit On-Demand spend to 20%, even if it means dropping user traffic during a Spot stockout:
*   **Do not use two independent HPAs.**
*   Instead, write a **Custom Kubernetes Controller / Operator**.
*   The operator should monitor the *actual Ready pods* of the Spot deployment, and dynamically set the desired replicas of the On-Demand deployment to match:
    $$\text{OD\_DesiredReplicas} = \lfloor \text{Spot\_ReadyReplicas} \times 0.25 \rfloor$$
*   If Spot nodes are stuck due to stockout, the operator will force the On-Demand pool to remain small, strictly guaranteeing the ratio.

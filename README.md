# GKE Spot and On-Demand Nodepool Ratio Scaling

This project demonstrates how to run a GKE service that spans across Spot and On-Demand nodepools, maintaining an 80% Spot and 20% On-Demand ratio of compute resources.

It uses standard Kubernetes HPA with matching proportional settings for min/max replicas, and GKE Cluster Autoscaler to dynamically scale both nodepools.

## Prerequisites

*   `gcloud` CLI installed and authenticated.
*   `kubectl` installed.
*   A Google Cloud Project with billing and Kubernetes Engine API enabled.

## Step-by-Step Instructions

### 1. Provision Cluster and Nodepools

Run the setup script to create a VPC network, subnet, GKE cluster, and two autoscaling nodepools:
*   `spot-pool`: Spot VMs, autoscaling 0-10 nodes, labeled `capacity-type=spot`.
*   `on-demand-pool`: On-Demand VMs, autoscaling 1-5 nodes, labeled `capacity-type=on-demand`.

```bash
./setup_cluster.sh
```

This script will also configure your `kubectl` context.

### 2. Deploy the Application

Deploy the namespace, deployments, service, and HPAs:
*   `ratio-app-spot` Deployment: 8 initial replicas, nodeSelector for `spot`, tolerations for spot taint.
*   `ratio-app-ondemand` Deployment: 2 initial replicas, nodeSelector for `on-demand`.
*   `ratio-app-service` Service: Exposes both deployments under a single IP.
*   HPAs:
    *   Spot HPA: min 8, max 80, target CPU 50%
    *   On-Demand HPA: min 2, max 20, target CPU 50%

```bash
./deploy_app.sh
```

*Note: The script might wait for a few minutes while GKE scales up the `spot-pool` from 0 nodes to accommodate the spot pods.*

---

### Option A: Dynamic Load Test Scaling (using HPA)

This method tests the end-to-end CPU-based scaling.

1.  Start the load test (scales up the load-generator deployment to 15 replicas):
    ```bash
    ./load_test.sh start 15
    ```
2.  Watch the scaling in real-time by running the monitoring script:
    ```bash
    ./list_pods.sh
    ```
    *(Observe the SUMMARY section at the bottom to see node and pod counts and ratios).*
3.  Stop the load test:
    ```bash
    ./load_test.sh stop
    ```

---

### Option B: Manual Scaling Simulation (Bypassing HPAs)

If you want to observe GKE node scaling immediately without waiting for CPU load to trigger the HPAs, you can scale the pods manually.

1.  Trigger manual scale-up (this deletes the HPAs temporarily to prevent them from scaling back down, then scales deployments to 40 Spot / 10 On-Demand):
    ```bash
    ./manual_scale.sh scale-up 40 10
    ```
2.  Immediately monitor the node provisioning and pod scheduling:
    ```bash
    ./list_pods.sh
    ```
    *   You will see many pods in `Pending / Unassigned` status.
    *   In the summary, you will see `Spot Nodes` and `On-Demand Nodes` start to increase as the GKE Cluster Autoscaler provisions new hardware.
    *   Eventually, all pods will transition to `Running` on their respective nodepools, and the summary will show the exact **80/20 ratio** of pods and nodes.
3.  Restore HPAs (this re-applies the HPAs, which will scale the pods back down to the baseline 8/2 since there is no load):
    ```bash
    ./manual_scale.sh restore
    ```

---

### 3. Cleanup

To delete all created resources (cluster, subnets, VPC) and avoid charges:

```bash
./cleanup.sh
```
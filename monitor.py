import json
import subprocess
import time
import sys

def run_kubectl(args):
    cmd = ["kubectl"] + args
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        # Don't spam errors if cluster is not ready yet
        return None

def get_deployment_replicas(name, namespace="ratio-app"):
    output = run_kubectl(["get", "deployment", name, "-n", namespace, "-o", "json"])
    if not output:
        return 0, 0
    try:
        data = json.loads(output)
        replicas = data.get("status", {}).get("replicas", 0)
        ready = data.get("status", {}).get("readyReplicas", 0)
        return replicas, ready
    except Exception:
        return 0, 0

def get_node_count(capacity_type):
    output = run_kubectl(["get", "nodes", "-l", f"capacity-type={capacity_type}", "-o", "json"])
    if not output:
        return 0
    try:
        data = json.loads(output)
        return len(data.get("items", []))
    except Exception:
        return 0

def get_hpa_status(name, namespace="ratio-app"):
    output = run_kubectl(["get", "hpa", name, "-n", namespace, "-o", "json"])
    if not output:
        return "N/A"
    try:
        data = json.loads(output)
        current_cpu = "N/A"
        current_metrics = data.get("status", {}).get("currentMetrics", [])
        for m in current_metrics:
            if m.get("type") == "Resource" and m.get("resource", {}).get("name") == "cpu":
                current_cpu = m.get("resource", {}).get("current", {}).get("averageUtilization", "N/A")
        return current_cpu
    except Exception:
        return "N/A"

def main():
    print("Starting resource monitor (Ctrl+C to exit)...")
    print(f"{'Time':<10} | {'Spot Pods (Rdy/Des)':<20} | {'OD Pods (Rdy/Des)':<20} | {'Pod Ratio (Spot/OD)':<22} | {'Spot Nodes':<10} | {'OD Nodes':<10} | {'Node Ratio':<12} | {'Spot CPU':<8} | {'OD CPU':<8}")
    print("-" * 135)
    
    while True:
        t = time.strftime("%H:%M:%S")
        
        spot_des, spot_rdy = get_deployment_replicas("ratio-app-spot")
        od_des, od_rdy = get_deployment_replicas("ratio-app-ondemand")
        
        spot_nodes = get_node_count("spot")
        od_nodes = get_node_count("on-demand")
        
        spot_cpu = get_hpa_status("ratio-app-spot-hpa")
        od_cpu = get_hpa_status("ratio-app-ondemand-hpa")
        
        # Calculate pod ratio
        total_pods = spot_rdy + od_rdy
        if total_pods > 0:
            pod_ratio_spot = (spot_rdy / total_pods) * 100
            pod_ratio_od = (od_rdy / total_pods) * 100
            pod_ratio_str = f"{pod_ratio_spot:.1f}% / {pod_ratio_od:.1f}%"
        else:
            pod_ratio_str = "N/A"
            
        # Calculate node ratio
        total_nodes = spot_nodes + od_nodes
        if total_nodes > 0:
            node_ratio_spot = (spot_nodes / total_nodes) * 100
            node_ratio_od = (od_nodes / total_nodes) * 100
            node_ratio_str = f"{node_ratio_spot:.1f}% / {node_ratio_od:.1f}%"
        else:
            node_ratio_str = "N/A"
            
        print(f"{t:<10} | {f'{spot_rdy}/{spot_des}':<20} | {f'{od_rdy}/{od_des}':<20} | {pod_ratio_str:<22} | {spot_nodes:<10} | {od_nodes:<10} | {node_ratio_str:<12} | {f'{spot_cpu}%':<8} | {f'{od_cpu}%':<8}")
        
        time.sleep(10)

if __name__ == "__main__":
    main()

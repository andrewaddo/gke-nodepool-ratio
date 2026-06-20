#!/bin/bash

NAMESPACE=${1:-ratio-app}

# Fetch nodes and build a mapping of node -> nodepool
declare -A node_to_pool
spot_nodes=0
ondemand_nodes=0
default_nodes=0

while read -r node pool cap; do
    if [ -n "$node" ]; then
        pool_str="$pool"
        if [ -n "$cap" ]; then
            pool_str="$pool ($cap)"
        fi
        node_to_pool["$node"]="$pool_str"
        
        if [ "$cap" = "spot" ]; then
            ((spot_nodes++))
        elif [ "$cap" = "on-demand" ]; then
            ((ondemand_nodes++))
        else
            ((default_nodes++))
        fi
    fi
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.cloud\.google\.com/gke-nodepool}{" "}{.metadata.labels.capacity-type}{"\n"}{end}')

# Fetch pods and print table
printf "%-50s | %-50s | %-30s | %-15s\n" "POD NAME" "NODE" "NODEPOOL" "STATUS"
printf '%.s-' {1..154}
printf '\n'

total_pods=0
spot_pods=0
ondemand_pods=0
other_pods=0
pending_pods=0

spot_running=0
spot_pending=0
ondemand_running=0
ondemand_pending=0

# Use IFS=$'\t' to read tab-separated values from go-template
while IFS=$'\t' read -r pod node status; do
    # Remove carriage return if any (for safety)
    status=$(echo "$status" | tr -d '\r')
    node=$(echo "$node" | tr -d '\r')
    pod=$(echo "$pod" | tr -d '\r')
    
    if [ -n "$pod" ]; then
        nodepool="N/A"
        if [ -n "$node" ] && [ "$node" != "none" ]; then
            nodepool="${node_to_pool[$node]:-N/A}"
        else
            node="Pending / Unassigned"
        fi
        
        if [ "$status" = "Pending" ]; then
            ((pending_pods++))
        fi
        
        printf "%-50s | %-50s | %-30s | %-15s\n" "$pod" "$node" "$nodepool" "$status"
        
        # Count for summary
        if [[ "$pod" =~ ^ratio-app-spot ]]; then
            ((spot_pods++))
            ((total_pods++))
            if [ "$status" = "Running" ]; then
                ((spot_running++))
            elif [ "$status" = "Pending" ]; then
                ((spot_pending++))
            fi
        elif [[ "$pod" =~ ^ratio-app-ondemand ]]; then
            ((ondemand_pods++))
            ((total_pods++))
            if [ "$status" = "Running" ]; then
                ((ondemand_running++))
            elif [ "$status" = "Pending" ]; then
                ((ondemand_pending++))
            fi
        else
            ((other_pods++))
        fi
    fi
done < <(kubectl get pods -n "$NAMESPACE" -o go-template='{{range .items}}{{.metadata.name}}{{"\t"}}{{if .spec.nodeName}}{{.spec.nodeName}}{{else}}{{"none"}}{{end}}{{"\t"}}{{.status.phase}}{{"\n"}}{{end}}')

# Print Summary
printf '\n'
printf '%.s=' {1..50}
printf '\n'
printf "%-30s\n" "SUMMARY"
printf '%.s-' {1..20}
printf '\n'
printf "%-30s : %d\n" "Total Nodes" $((spot_nodes + ondemand_nodes + default_nodes))
printf "  - Spot Nodes                 : %d\n" "$spot_nodes"
printf "  - On-Demand Nodes            : %d\n" "$ondemand_nodes"
printf "  - Default Nodes              : %d\n" "$default_nodes"
printf "%-30s : %d\n" "Total App Pods" "$total_pods"
printf "  - Spot Pods                  : %d (Running: %d, Pending: %d)\n" "$spot_pods" "$spot_running" "$spot_pending"
printf "  - On-Demand Pods             : %d (Running: %d, Pending: %d)\n" "$ondemand_pods" "$ondemand_running" "$ondemand_pending"
printf "%-30s : %d\n" "Other Pods (e.g. Load Gen)" "$other_pods"
printf "%-30s : %d\n" "Pending Pods (Total)" "$pending_pods"

# Calculate Ratios
total_active_app_pods=$((spot_pods + ondemand_pods))
if [ $total_active_app_pods -gt 0 ]; then
    spot_pod_ratio=$(awk "BEGIN {print ($spot_pods/$total_active_app_pods)*100}")
    od_pod_ratio=$(awk "BEGIN {print ($ondemand_pods/$total_active_app_pods)*100}")
    printf "App Pod Ratio (Spot/OD)      : %.1f%% / %.1f%%\n" "$spot_pod_ratio" "$od_pod_ratio"
fi

total_app_nodes=$((spot_nodes + ondemand_nodes))
if [ $total_app_nodes -gt 0 ]; then
    spot_node_ratio=$(awk "BEGIN {print ($spot_nodes/$total_app_nodes)*100}")
    od_node_ratio=$(awk "BEGIN {print ($ondemand_nodes/$total_app_nodes)*100}")
    printf "App Node Ratio (Spot/OD)     : %.1f%% / %.1f%%\n" "$spot_node_ratio" "$od_node_ratio"
fi
printf '%.s=' {1..50}
printf '\n'

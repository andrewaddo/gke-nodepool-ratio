#!/bin/bash
set -e

ACTION=$1

if [ -z "$ACTION" ]; then
  echo "Usage: $0 [scale-up|restore] [spot_replicas] [od_replicas]"
  echo "  Example: $0 scale-up 40 10"
  exit 1
fi

case "$ACTION" in
  scale-up)
    SPOT_REPLICAS=${2:-40}
    OD_REPLICAS=${3:-10}
    
    echo "Temporarily deleting HPAs to allow manual scaling..."
    kubectl delete hpa ratio-app-spot-hpa -n ratio-app --ignore-not-found
    kubectl delete hpa ratio-app-ondemand-hpa -n ratio-app --ignore-not-found
    
    echo "Manually scaling deployments to maintain 80/20 ratio..."
    echo "Scaling Spot to $SPOT_REPLICAS..."
    kubectl scale deployment ratio-app-spot -n ratio-app --replicas=$SPOT_REPLICAS
    echo "Scaling On-Demand to $OD_REPLICAS..."
    kubectl scale deployment ratio-app-ondemand -n ratio-app --replicas=$OD_REPLICAS
    
    echo "Manual scale-up triggered. Run ./list_pods.sh to monitor."
    ;;
    
  restore)
    echo "Restoring HPAs..."
    kubectl apply -f k8s/hpa-spot.yaml
    kubectl apply -f k8s/hpa-ondemand.yaml
    echo "HPAs restored. They will automatically adjust replicas based on current load."
    ;;
    
  *)
    echo "Invalid action: $ACTION"
    exit 1
    ;;
esac

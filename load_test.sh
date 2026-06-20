#!/bin/bash
set -e

ACTION=$1
REPLICAS=${2:-10} # Default to 10 replicas for load

if [ -z "$ACTION" ]; then
  echo "Usage: $0 [start|stop|status] [num_replicas]"
  exit 1
fi

case "$ACTION" in
  start)
    echo "Starting load test with $REPLICAS generator pods..."
    kubectl scale deployment load-generator -n ratio-app --replicas=$REPLICAS
    ;;
  stop)
    echo "Stopping load test..."
    kubectl scale deployment load-generator -n ratio-app --replicas=0
    ;;
  status)
    kubectl get deployment load-generator -n ratio-app
    ;;
  *)
    echo "Invalid action: $ACTION. Use start, stop, or status."
    exit 1
    ;;
esac

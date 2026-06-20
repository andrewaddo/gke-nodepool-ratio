#!/bin/bash
set -e

# Apply namespace
kubectl apply -f k8s/namespace.yaml

# Apply deployments and service
kubectl apply -f k8s/deployment-spot.yaml
kubectl apply -f k8s/deployment-ondemand.yaml
kubectl apply -f k8s/service.yaml

# Apply HPAs
kubectl apply -f k8s/hpa-spot.yaml
kubectl apply -f k8s/hpa-ondemand.yaml

# Apply Load Generator
kubectl apply -f k8s/load-generator.yaml

echo "Deployment submitted. Waiting for pods to be ready..."
kubectl wait --namespace=ratio-app --for=condition=ready pod --selector=app=ratio-app --timeout=300s

echo "All pods ready!"
kubectl get pods -n ratio-app -o wide
kubectl get hpa -n ratio-app

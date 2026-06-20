#!/bin/bash
# Exit on error
set -e

PROJECT_ID=$(gcloud config get-value project)
REGION="asia-southeast1"
ZONE="asia-southeast1-a"
NETWORK_NAME="ratio-net"
SUBNET_NAME="ratio-subnet"
CLUSTER_NAME="ratio-cluster"

echo "Using project: $PROJECT_ID"

# 1. Delete GKE Cluster
if gcloud container clusters describe $CLUSTER_NAME --project=$PROJECT_ID --zone=$ZONE >/dev/null 2>&1; then
  echo "Deleting GKE cluster $CLUSTER_NAME..."
  gcloud container clusters delete $CLUSTER_NAME --project=$PROJECT_ID --zone=$ZONE --quiet
else
  echo "Cluster $CLUSTER_NAME does not exist."
fi

# 2. Delete Subnet
if gcloud compute networks subnets describe $SUBNET_NAME --project=$PROJECT_ID --region=$REGION >/dev/null 2>&1; then
  echo "Deleting subnet $SUBNET_NAME..."
  gcloud compute networks subnets delete $SUBNET_NAME --project=$PROJECT_ID --region=$REGION --quiet
else
  echo "Subnet $SUBNET_NAME does not exist."
fi

# 3. Delete VPC Network
if gcloud compute networks describe $NETWORK_NAME --project=$PROJECT_ID >/dev/null 2>&1; then
  echo "Deleting network $NETWORK_NAME..."
  gcloud compute networks delete $NETWORK_NAME --project=$PROJECT_ID --quiet
else
  echo "Network $NETWORK_NAME does not exist."
fi

echo "Cleanup complete!"

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

# 1. Create VPC Network
if ! gcloud compute networks describe $NETWORK_NAME --project=$PROJECT_ID >/dev/null 2>&1; then
  echo "Creating network $NETWORK_NAME..."
  gcloud compute networks create $NETWORK_NAME \
      --project=$PROJECT_ID \
      --subnet-mode=custom
else
  echo "Network $NETWORK_NAME already exists."
fi

# 2. Create Subnet
if ! gcloud compute networks subnets describe $SUBNET_NAME --project=$PROJECT_ID --region=$REGION >/dev/null 2>&1; then
  echo "Creating subnet $SUBNET_NAME..."
  gcloud compute networks subnets create $SUBNET_NAME \
      --project=$PROJECT_ID \
      --network=$NETWORK_NAME \
      --region=$REGION \
      --range=10.0.0.0/20 \
      --enable-private-ip-google-access
else
  echo "Subnet $SUBNET_NAME already exists."
fi

# 3. Create GKE Cluster
# We create it with a small default pool and immediately disable it or use it for system pods.
# Actually, we can create it without default nodepool if we use --no-enable-default-node-pool,
# but we must specify a nodepool to create.
# Alternatively, we create it with default nodepool of 1 node, and we will use it for system workloads.
if ! gcloud container clusters describe $CLUSTER_NAME --project=$PROJECT_ID --zone=$ZONE >/dev/null 2>&1; then
  echo "Creating GKE cluster $CLUSTER_NAME..."
  gcloud container clusters create $CLUSTER_NAME \
      --project=$PROJECT_ID \
      --zone=$ZONE \
      --network=$NETWORK_NAME \
      --subnetwork=$SUBNET_NAME \
      --num-nodes=1 \
      --machine-type=e2-standard-2 \
      --enable-ip-alias \
      --workload-pool=$PROJECT_ID.svc.id.goog
else
  echo "Cluster $CLUSTER_NAME already exists."
fi

# Get credentials
gcloud container clusters get-credentials $CLUSTER_NAME --project=$PROJECT_ID --zone=$ZONE

# The default nodepool will be our "system" or we can rename it.
# Actually, let's create the two specific nodepools: spot-pool and on-demand-pool.

# 4. Create Spot Nodepool
# We want it to be Spot.
# We set autoscaling.
# We taint it so only our app pods with tolerations land there.
# We also label it.
SPOT_POOL_NAME="spot-pool"
if ! gcloud container node-pools describe $SPOT_POOL_NAME --cluster=$CLUSTER_NAME --project=$PROJECT_ID --zone=$ZONE >/dev/null 2>&1; then
  echo "Creating spot nodepool $SPOT_POOL_NAME..."
  gcloud container node-pools create $SPOT_POOL_NAME \
      --cluster=$CLUSTER_NAME \
      --project=$PROJECT_ID \
      --zone=$ZONE \
      --spot \
      --machine-type=e2-standard-2 \
      --num-nodes=0 \
      --enable-autoscaling \
      --min-nodes=0 \
      --max-nodes=10 \
      --node-labels=capacity-type=spot \
      --node-taints=cloud.google.com/gke-spot=true:NoSchedule
else
  echo "Nodepool $SPOT_POOL_NAME already exists."
fi

# 5. Create On-Demand Nodepool
ONDEMAND_POOL_NAME="on-demand-pool"
if ! gcloud container node-pools describe $ONDEMAND_POOL_NAME --cluster=$CLUSTER_NAME --project=$PROJECT_ID --zone=$ZONE >/dev/null 2>&1; then
  echo "Creating on-demand nodepool $ONDEMAND_POOL_NAME..."
  gcloud container node-pools create $ONDEMAND_POOL_NAME \
      --cluster=$CLUSTER_NAME \
      --project=$PROJECT_ID \
      --zone=$ZONE \
      --machine-type=e2-standard-2 \
      --num-nodes=1 \
      --enable-autoscaling \
      --min-nodes=1 \
      --max-nodes=5 \
      --node-labels=capacity-type=on-demand
else
  echo "Nodepool $ONDEMAND_POOL_NAME already exists."
fi

echo "Setup complete!"

#!/bin/bash
# Create production AKS cluster with all recommended settings
set -euo pipefail

# ── Variables ─────────────────────────────────────────────────────────────────
RG="rg-aks-microservices-prod-eastus"
LOCATION="eastus"
CLUSTER_NAME="aks-microservices-prod"
ACR_NAME="acrmicrservicesprod"
LAW_NAME="law-aks-prod"
VNET_NAME="vnet-aks-prod"
NODE_SUBNET="snet-nodes"
POD_SUBNET="snet-pods"
K8S_VERSION="1.29"

echo "=== Creating AKS Microservices Cluster ==="
echo "Resource Group: $RG | Location: $LOCATION"

# ── Resource Group ────────────────────────────────────────────────────────────
az group create \
  --name $RG \
  --location $LOCATION \
  --tags Environment=production Application=microservices

# ── Log Analytics Workspace ───────────────────────────────────────────────────
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name $LAW_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time 90 \
  --query id --output tsv)
echo "Log Analytics: $LAW_ID"

# ── Container Registry ────────────────────────────────────────────────────────
az acr create \
  --name $ACR_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Premium \
  --admin-enabled false \
  --zone-redundancy enabled
echo "ACR created: $ACR_NAME"

# ── Virtual Network ───────────────────────────────────────────────────────────
az network vnet create \
  --name $VNET_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix 10.0.0.0/8

NODE_SUBNET_ID=$(az network vnet subnet create \
  --name $NODE_SUBNET \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --address-prefix 10.240.0.0/16 \
  --query id --output tsv)

POD_SUBNET_ID=$(az network vnet subnet create \
  --name $POD_SUBNET \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --address-prefix 10.241.0.0/16 \
  --query id --output tsv)

echo "VNet and subnets created"

# ── AKS Cluster ───────────────────────────────────────────────────────────────
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --location $LOCATION \
  --kubernetes-version $K8S_VERSION \
  --node-count 3 \
  --node-vm-size Standard_D4s_v5 \
  --os-disk-size-gb 128 \
  --os-disk-type Ephemeral \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10 \
  --zones 1 2 3 \
  --network-plugin azure \
  --network-policy azure \
  --vnet-subnet-id $NODE_SUBNET_ID \
  --pod-subnet-id $POD_SUBNET_ID \
  --service-cidr 10.0.0.0/16 \
  --dns-service-ip 10.0.0.10 \
  --enable-managed-identity \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --enable-addons monitoring,azure-policy \
  --workspace-resource-id $LAW_ID \
  --attach-acr $ACR_NAME \
  --enable-secret-rotation \
  --rotation-poll-interval 2m \
  --node-os-upgrade-channel NodeImage \
  --auto-upgrade-channel patch \
  --uptime-sla \
  --generate-ssh-keys \
  --tags Environment=production Application=microservices

echo "AKS cluster created: $CLUSTER_NAME"

# ── Add GPU Node Pool (optional) ──────────────────────────────────────────────
# az aks nodepool add \
#   --resource-group $RG \
#   --cluster-name $CLUSTER_NAME \
#   --name gpupool \
#   --node-count 1 \
#   --node-vm-size Standard_NC6s_v3 \
#   --node-taints sku=gpu:NoSchedule \
#   --labels hardware=gpu

# ── Add Spot Node Pool for batch workloads ────────────────────────────────────
az aks nodepool add \
  --resource-group $RG \
  --cluster-name $CLUSTER_NAME \
  --name spotpool \
  --node-count 0 \
  --node-vm-size Standard_D4s_v5 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 20 \
  --node-taints kubernetes.azure.com/scalesetpriority=spot:NoSchedule \
  --labels kubernetes.azure.com/scalesetpriority=spot

echo "Spot node pool added"

# ── Get Credentials ───────────────────────────────────────────────────────────
az aks get-credentials \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --overwrite-existing

echo "Kubeconfig updated"

# ── Install NGINX Ingress Controller ─────────────────────────────────────────
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set controller.service.externalTrafficPolicy=Local

echo "NGINX Ingress installed"

# ── Install cert-manager ──────────────────────────────────────────────────────
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

echo "cert-manager installed"

# ── Install KEDA (event-driven autoscaling) ───────────────────────────────────
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace

echo "KEDA installed"

# ── Apply base manifests ──────────────────────────────────────────────────────
kubectl apply -f ../k8s/namespace.yaml

echo ""
echo "=== Cluster Setup Complete ==="
echo "Cluster: $CLUSTER_NAME"
echo "ACR: $ACR_NAME.azurecr.io"
echo ""
echo "Next steps:"
echo "  1. Run ./build-push.sh to build and push images"
echo "  2. Create secrets: kubectl create secret generic order-db-secret ..."
echo "  3. Apply manifests: kubectl apply -f ../k8s/"
echo "  4. Check pods: kubectl get pods -n production"

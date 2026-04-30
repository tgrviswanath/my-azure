#!/bin/bash
# Project 03 — AKS Microservices: Create Cluster Script
set -euo pipefail

RG="rg-aks-microservices-prod-eastus"
LOCATION="eastus"
CLUSTER="aks-microservices-prod"
ACR_NAME="acrmicroservicesprod$(openssl rand -hex 4)"
LAW_NAME="law-aks-prod"

echo "🚀 Creating AKS Microservices Infrastructure"
az group create --name $RG --location $LOCATION --tags Project=AKSMicroservices Environment=prod

# Log Analytics
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name $LAW_NAME --resource-group $RG --location $LOCATION \
  --sku PerGB2018 --retention-time 90 --query id --output tsv)

# ACR
az acr create --name $ACR_NAME --resource-group $RG --sku Premium \
  --admin-enabled false --zone-redundancy enabled

# VNet for AKS
az network vnet create --name vnet-aks-prod --resource-group $RG \
  --location $LOCATION --address-prefix 10.0.0.0/8

az network vnet subnet create --name snet-aks-nodes --resource-group $RG \
  --vnet-name vnet-aks-prod --address-prefix 10.240.0.0/16

SUBNET_ID=$(az network vnet subnet show --name snet-aks-nodes \
  --resource-group $RG --vnet-name vnet-aks-prod --query id --output tsv)

# AKS Cluster
az aks create \
  --resource-group $RG \
  --name $CLUSTER \
  --kubernetes-version 1.28 \
  --node-count 3 \
  --node-vm-size Standard_D4s_v5 \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10 \
  --network-plugin azure \
  --network-policy azure \
  --vnet-subnet-id $SUBNET_ID \
  --enable-managed-identity \
  --enable-addons monitoring,azure-policy,azure-keyvault-secrets-provider \
  --workspace-resource-id $LAW_ID \
  --zones 1 2 3 \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --generate-ssh-keys \
  --attach-acr $ACR_NAME \
  --tags Environment=prod Project=AKSMicroservices

# Get credentials
az aks get-credentials --resource-group $RG --name $CLUSTER --overwrite-existing

# Create namespaces
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace staging    --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

echo ""
echo "✅ AKS cluster created!"
echo "   Cluster: $CLUSTER"
echo "   ACR:     $ACR_NAME"
echo ""
echo "Next: ./build-push.sh to build and push images"
kubectl get nodes

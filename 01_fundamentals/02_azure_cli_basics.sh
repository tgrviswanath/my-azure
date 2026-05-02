#!/bin/bash
# Azure CLI Basics — Essential Commands Reference
# Run: chmod +x 02_azure_cli_basics.sh && ./02_azure_cli_basics.sh

set -euo pipefail

# ── Authentication ────────────────────────────────────────────────────────────
az login                                          # Interactive browser login
az login --service-principal \
  --username $APP_ID \
  --password $PASSWORD \
  --tenant $TENANT_ID                             # Service principal login

az account show                                   # Current subscription
az account list --output table                    # All subscriptions
az account set --subscription "SUBSCRIPTION_ID"  # Switch subscription

# ── Resource Groups ───────────────────────────────────────────────────────────
RG="rg-demo-dev-eastus"
LOCATION="eastus"

az group create \
  --name $RG \
  --location $LOCATION \
  --tags Environment=Dev Project=Demo

az group list --output table
az group show --name $RG
az group delete --name $RG --yes --no-wait

# ── Virtual Machines ──────────────────────────────────────────────────────────
VM_NAME="vm-web-dev-001"
VM_SIZE="Standard_B2s"
IMAGE="Ubuntu2204"
ADMIN_USER="azureuser"

# Create VM
az vm create \
  --resource-group $RG \
  --name $VM_NAME \
  --image $IMAGE \
  --size $VM_SIZE \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --tags Environment=Dev Role=WebServer

# VM operations
az vm start  --resource-group $RG --name $VM_NAME
az vm stop   --resource-group $RG --name $VM_NAME
az vm restart --resource-group $RG --name $VM_NAME
az vm deallocate --resource-group $RG --name $VM_NAME  # Stop billing for compute
az vm delete --resource-group $RG --name $VM_NAME --yes

# List VMs
az vm list --resource-group $RG --output table
az vm list-sizes --location $LOCATION --output table

# Get VM IP
az vm show \
  --resource-group $RG \
  --name $VM_NAME \
  --show-details \
  --query publicIps \
  --output tsv

# Open port
az vm open-port --resource-group $RG --name $VM_NAME --port 80

# ── Storage Accounts ──────────────────────────────────────────────────────────
STORAGE_NAME="stdemoprod$(date +%s)"  # Must be globally unique, 3-24 chars, lowercase

az storage account create \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --access-tier Hot \
  --https-only true \
  --min-tls-version TLS1_2

# Get connection string
CONN_STR=$(az storage account show-connection-string \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --query connectionString \
  --output tsv)

# Create blob container
az storage container create \
  --name "uploads" \
  --account-name $STORAGE_NAME \
  --public-access off

# Upload blob
az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name "uploads" \
  --name "test.txt" \
  --file "./test.txt"

# List blobs
az storage blob list \
  --account-name $STORAGE_NAME \
  --container-name "uploads" \
  --output table

# ── App Service ───────────────────────────────────────────────────────────────
APP_PLAN="asp-webapp-dev"
APP_NAME="app-webapp-dev-$(date +%s)"

# Create App Service Plan
az appservice plan create \
  --name $APP_PLAN \
  --resource-group $RG \
  --location $LOCATION \
  --sku B1 \
  --is-linux

# Create Web App
az webapp create \
  --name $APP_NAME \
  --resource-group $RG \
  --plan $APP_PLAN \
  --runtime "NODE:18-lts"

# Deploy from GitHub
az webapp deployment source config \
  --name $APP_NAME \
  --resource-group $RG \
  --repo-url "https://github.com/user/repo" \
  --branch main \
  --manual-integration

# App settings
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RG \
  --settings \
    NODE_ENV=production \
    DATABASE_URL="@Microsoft.KeyVault(SecretUri=...)"

# ── Azure Functions ───────────────────────────────────────────────────────────
FUNC_APP="func-api-dev-$(date +%s)"
FUNC_STORAGE="stfuncdev$(date +%s)"

# Create storage for function app
az storage account create \
  --name $FUNC_STORAGE \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS

# Create function app
az functionapp create \
  --name $FUNC_APP \
  --resource-group $RG \
  --storage-account $FUNC_STORAGE \
  --consumption-plan-location $LOCATION \
  --runtime node \
  --runtime-version 18 \
  --functions-version 4 \
  --os-type Linux

# ── Key Vault ─────────────────────────────────────────────────────────────────
KV_NAME="kv-demo-dev-$(date +%s)"

az keyvault create \
  --name $KV_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku standard \
  --enable-rbac-authorization true

# Add secret
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "DatabasePassword" \
  --value "SuperSecretPassword123!"

# Get secret
az keyvault secret show \
  --vault-name $KV_NAME \
  --name "DatabasePassword" \
  --query value \
  --output tsv

# ── Networking ────────────────────────────────────────────────────────────────
VNET_NAME="vnet-app-dev"
SUBNET_WEB="snet-web"
SUBNET_DB="snet-db"

# Create VNet
az network vnet create \
  --name $VNET_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16

# Create subnets
az network vnet subnet create \
  --name $SUBNET_WEB \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --address-prefix 10.0.1.0/24

az network vnet subnet create \
  --name $SUBNET_DB \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --address-prefix 10.0.2.0/24

# Create NSG
NSG_NAME="nsg-web-dev"
az network nsg create \
  --name $NSG_NAME \
  --resource-group $RG \
  --location $LOCATION

# Add NSG rules
az network nsg rule create \
  --name "AllowHTTPS" \
  --nsg-name $NSG_NAME \
  --resource-group $RG \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-range 443

az network nsg rule create \
  --name "DenyAllInbound" \
  --nsg-name $NSG_NAME \
  --resource-group $RG \
  --priority 4096 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --destination-port-range "*"

# ── Monitoring ────────────────────────────────────────────────────────────────
# Create Log Analytics workspace
LAW_NAME="law-demo-dev"
az monitor log-analytics workspace create \
  --workspace-name $LAW_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time 30

# Create alert rule
az monitor metrics alert create \
  --name "HighCPUAlert" \
  --resource-group $RG \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --description "Alert when CPU > 80%"

# ── Useful Queries ────────────────────────────────────────────────────────────
# List all resources in subscription
az resource list --output table

# List resources by type
az resource list --resource-type "Microsoft.Compute/virtualMachines" --output table

# Get resource costs (requires Cost Management)
az consumption usage list \
  --start-date $(date -d "30 days ago" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --output table

# Tag all resources in a group
az resource list --resource-group $RG --query "[].id" --output tsv | \
  xargs -I {} az resource tag --ids {} --tags Environment=Dev

echo "Azure CLI basics complete!"

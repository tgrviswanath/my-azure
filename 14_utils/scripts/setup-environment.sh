#!/bin/bash
# Azure Environment Setup Script
# Sets up a complete Azure environment with best practices
# Usage: ./setup-environment.sh <environment> <app-name> <location>
# Example: ./setup-environment.sh prod myapp eastus

set -euo pipefail

ENVIRONMENT="${1:-dev}"
APP_NAME="${2:-myapp}"
LOCATION="${3:-eastus}"
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)

echo "=== Azure Environment Setup ==="
echo "Environment: $ENVIRONMENT | App: $APP_NAME | Location: $LOCATION"
echo "Subscription: $SUBSCRIPTION_ID"
echo ""

# ── Naming Convention ─────────────────────────────────────────────────────────
RG="rg-${APP_NAME}-${ENVIRONMENT}-${LOCATION}"
VNET="vnet-${APP_NAME}-${ENVIRONMENT}"
LAW="law-${APP_NAME}-${ENVIRONMENT}"
KV="kv-${APP_NAME}-${ENVIRONMENT}-$(echo $SUBSCRIPTION_ID | cut -c1-8)"
ACR="acr${APP_NAME}${ENVIRONMENT}"
STORAGE="st${APP_NAME}${ENVIRONMENT}$(echo $SUBSCRIPTION_ID | tr -d '-' | cut -c1-8)"

# ── Resource Group ────────────────────────────────────────────────────────────
echo "1. Creating Resource Group..."
az group create \
  --name $RG \
  --location $LOCATION \
  --tags \
    Environment=$ENVIRONMENT \
    Application=$APP_NAME \
    ManagedBy=Script \
    CreatedDate=$(date +%Y-%m-%d)

# ── Log Analytics Workspace ───────────────────────────────────────────────────
echo "2. Creating Log Analytics Workspace..."
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name $LAW \
  --resource-group $RG \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time $([ "$ENVIRONMENT" = "prod" ] && echo 90 || echo 30) \
  --query id --output tsv)
echo "   Log Analytics: $LAW_ID"

# ── Key Vault ─────────────────────────────────────────────────────────────────
echo "3. Creating Key Vault..."
az keyvault create \
  --name $KV \
  --resource-group $RG \
  --location $LOCATION \
  --sku standard \
  --enable-rbac-authorization true \
  --enable-soft-delete true \
  --soft-delete-retention-days $([ "$ENVIRONMENT" = "prod" ] && echo 90 || echo 7) \
  --enable-purge-protection $([ "$ENVIRONMENT" = "prod" ] && echo true || echo false) \
  --retention-days $([ "$ENVIRONMENT" = "prod" ] && echo 90 || echo 7)

KV_ID=$(az keyvault show --name $KV --resource-group $RG --query id --output tsv)
echo "   Key Vault: $KV_ID"

# Grant current user Key Vault admin
CURRENT_USER=$(az ad signed-in-user show --query id --output tsv 2>/dev/null || echo "")
if [ -n "$CURRENT_USER" ]; then
  az role assignment create \
    --assignee $CURRENT_USER \
    --role "Key Vault Administrator" \
    --scope $KV_ID
fi

# ── Storage Account ───────────────────────────────────────────────────────────
echo "4. Creating Storage Account..."
az storage account create \
  --name $STORAGE \
  --resource-group $RG \
  --location $LOCATION \
  --sku $([ "$ENVIRONMENT" = "prod" ] && echo Standard_ZRS || echo Standard_LRS) \
  --kind StorageV2 \
  --access-tier Hot \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --tags Environment=$ENVIRONMENT Application=$APP_NAME

STORAGE_ID=$(az storage account show --name $STORAGE --resource-group $RG --query id --output tsv)
echo "   Storage: $STORAGE_ID"

# ── Container Registry ────────────────────────────────────────────────────────
echo "5. Creating Container Registry..."
az acr create \
  --name $ACR \
  --resource-group $RG \
  --location $LOCATION \
  --sku $([ "$ENVIRONMENT" = "prod" ] && echo Premium || echo Basic) \
  --admin-enabled false \
  --tags Environment=$ENVIRONMENT Application=$APP_NAME

ACR_ID=$(az acr show --name $ACR --resource-group $RG --query id --output tsv)
echo "   ACR: $ACR_ID"

# ── Virtual Network ───────────────────────────────────────────────────────────
echo "6. Creating Virtual Network..."
az network vnet create \
  --name $VNET \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16 \
  --tags Environment=$ENVIRONMENT Application=$APP_NAME

# App subnet (with service endpoints)
az network vnet subnet create \
  --name snet-app \
  --resource-group $RG \
  --vnet-name $VNET \
  --address-prefix 10.0.1.0/24 \
  --service-endpoints Microsoft.Storage Microsoft.Sql Microsoft.KeyVault

# Database subnet
az network vnet subnet create \
  --name snet-db \
  --resource-group $RG \
  --vnet-name $VNET \
  --address-prefix 10.0.2.0/24 \
  --disable-private-endpoint-network-policies true

# Private endpoint subnet
az network vnet subnet create \
  --name snet-pe \
  --resource-group $RG \
  --vnet-name $VNET \
  --address-prefix 10.0.3.0/24 \
  --disable-private-endpoint-network-policies true

echo "   VNet and subnets created"

# ── Application Insights ──────────────────────────────────────────────────────
echo "7. Creating Application Insights..."
AI_CONNECTION=$(az monitor app-insights component create \
  --app "ai-${APP_NAME}-${ENVIRONMENT}" \
  --resource-group $RG \
  --location $LOCATION \
  --kind web \
  --workspace $LAW_ID \
  --query connectionString --output tsv)
echo "   App Insights connected"

# ── Store secrets in Key Vault ────────────────────────────────────────────────
echo "8. Storing configuration in Key Vault..."
az keyvault secret set \
  --vault-name $KV \
  --name "AppInsightsConnectionString" \
  --value "$AI_CONNECTION" > /dev/null

az keyvault secret set \
  --vault-name $KV \
  --name "StorageAccountName" \
  --value "$STORAGE" > /dev/null

echo "   Secrets stored"

# ── Output Summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Environment Setup Complete ==="
echo ""
echo "Resource Group:    $RG"
echo "Key Vault:         $KV"
echo "Storage Account:   $STORAGE"
echo "Container Registry: $ACR.azurecr.io"
echo "Log Analytics:     $LAW"
echo "VNet:              $VNET"
echo ""
echo "Next steps:"
echo "  1. Deploy application: az webapp create ..."
echo "  2. Configure private endpoints for SQL/Redis"
echo "  3. Set up CI/CD pipeline"
echo ""
echo "Save these values:"
echo "  export RG=$RG"
echo "  export KV=$KV"
echo "  export STORAGE=$STORAGE"
echo "  export ACR=$ACR"
echo "  export LAW_ID=$LAW_ID"

#!/bin/bash
# Project 01 — Scalable Web App Deployment Script
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"
LOCATION="eastus"
LOCATION_DR="westeurope"
APP_NAME="mywebapp"
ENVIRONMENT="prod"
RG="rg-${APP_NAME}-${ENVIRONMENT}-${LOCATION}"
RG_DR="rg-${APP_NAME}-${ENVIRONMENT}-${LOCATION_DR}"

echo "🚀 Deploying Scalable Web App to Azure"
echo "   Subscription: $SUBSCRIPTION_ID"
echo "   Primary Region: $LOCATION"
echo "   DR Region: $LOCATION_DR"

# ── Login & Set Subscription ──────────────────────────────────────────────────
az account set --subscription "$SUBSCRIPTION_ID"

# ── Create Resource Groups ────────────────────────────────────────────────────
echo "📁 Creating resource groups..."
az group create --name "$RG"    --location "$LOCATION"    --tags Environment=$ENVIRONMENT Project=$APP_NAME
az group create --name "$RG_DR" --location "$LOCATION_DR" --tags Environment=$ENVIRONMENT Project=$APP_NAME

# ── Log Analytics ─────────────────────────────────────────────────────────────
echo "📊 Creating Log Analytics workspace..."
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name "law-${APP_NAME}-${ENVIRONMENT}" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku PerGB2018 \
  --retention-time 90 \
  --query id --output tsv)

# ── Application Insights ──────────────────────────────────────────────────────
echo "🔍 Creating Application Insights..."
AI_KEY=$(az monitor app-insights component create \
  --app "ai-${APP_NAME}-${ENVIRONMENT}" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --workspace "$LAW_ID" \
  --query instrumentationKey --output tsv)

AI_CONN=$(az monitor app-insights component show \
  --app "ai-${APP_NAME}-${ENVIRONMENT}" \
  --resource-group "$RG" \
  --query connectionString --output tsv)

# ── Key Vault ─────────────────────────────────────────────────────────────────
echo "🔐 Creating Key Vault..."
KV_NAME="kv-${APP_NAME}-${ENVIRONMENT}-$(openssl rand -hex 3)"
az keyvault create \
  --name "$KV_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku standard \
  --enable-rbac-authorization true \
  --enable-soft-delete true \
  --soft-delete-retention-days 90 \
  --enable-purge-protection true

# ── Storage Account ───────────────────────────────────────────────────────────
echo "💾 Creating Storage Account..."
STORAGE_NAME="st${APP_NAME}${ENVIRONMENT}$(openssl rand -hex 3)"
az storage account create \
  --name "$STORAGE_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# ── SQL Server (Primary) ──────────────────────────────────────────────────────
echo "🗄️ Creating SQL Server (primary)..."
SQL_PASSWORD=$(openssl rand -base64 32)
SQL_SERVER_PRIMARY="sql-${APP_NAME}-${ENVIRONMENT}-primary"

az sql server create \
  --name "$SQL_SERVER_PRIMARY" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --admin-user sqladmin \
  --admin-password "$SQL_PASSWORD" \
  --enable-public-network false

# Store SQL password in Key Vault
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "SqlAdminPassword" \
  --value "$SQL_PASSWORD"

# Create database
az sql db create \
  --name "${APP_NAME}-db" \
  --server "$SQL_SERVER_PRIMARY" \
  --resource-group "$RG" \
  --service-objective BC_Gen5_4 \
  --zone-redundant true \
  --backup-storage-redundancy Zone

# ── SQL Server (DR) ───────────────────────────────────────────────────────────
echo "🗄️ Creating SQL Server (DR)..."
SQL_SERVER_DR="sql-${APP_NAME}-${ENVIRONMENT}-dr"
az sql server create \
  --name "$SQL_SERVER_DR" \
  --resource-group "$RG_DR" \
  --location "$LOCATION_DR" \
  --admin-user sqladmin \
  --admin-password "$SQL_PASSWORD" \
  --enable-public-network false

# Failover group
az sql failover-group create \
  --name "fog-${APP_NAME}" \
  --server "$SQL_SERVER_PRIMARY" \
  --resource-group "$RG" \
  --partner-server "$SQL_SERVER_DR" \
  --failover-policy Automatic \
  --grace-period 1 \
  --add-db "${APP_NAME}-db"

# ── App Service Plan ──────────────────────────────────────────────────────────
echo "⚙️ Creating App Service Plans..."
az appservice plan create \
  --name "asp-${APP_NAME}-${ENVIRONMENT}" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku P2v3 \
  --is-linux \
  --number-of-workers 2

az appservice plan create \
  --name "asp-${APP_NAME}-${ENVIRONMENT}-dr" \
  --resource-group "$RG_DR" \
  --location "$LOCATION_DR" \
  --sku P2v3 \
  --is-linux \
  --number-of-workers 2

# ── Web Apps ──────────────────────────────────────────────────────────────────
echo "🌐 Creating Web Apps..."
APP_PRIMARY="app-${APP_NAME}-${ENVIRONMENT}"
APP_DR="app-${APP_NAME}-${ENVIRONMENT}-dr"

for APP_INSTANCE in "$APP_PRIMARY" "$APP_DR"; do
  PLAN_RG="$RG"
  PLAN_NAME="asp-${APP_NAME}-${ENVIRONMENT}"
  if [ "$APP_INSTANCE" == "$APP_DR" ]; then
    PLAN_RG="$RG_DR"
    PLAN_NAME="asp-${APP_NAME}-${ENVIRONMENT}-dr"
  fi

  az webapp create \
    --name "$APP_INSTANCE" \
    --resource-group "${PLAN_RG}" \
    --plan "$PLAN_NAME" \
    --runtime "NODE:18-lts" \
    --https-only true

  # Enable managed identity
  az webapp identity assign \
    --name "$APP_INSTANCE" \
    --resource-group "${PLAN_RG}"

  # App settings
  az webapp config appsettings set \
    --name "$APP_INSTANCE" \
    --resource-group "${PLAN_RG}" \
    --settings \
      APPLICATIONINSIGHTS_CONNECTION_STRING="$AI_CONN" \
      NODE_ENV=production \
      STORAGE_ACCOUNT_NAME="$STORAGE_NAME"
done

# ── Auto-scaling ──────────────────────────────────────────────────────────────
echo "📈 Configuring auto-scaling..."
PLAN_ID=$(az appservice plan show \
  --name "asp-${APP_NAME}-${ENVIRONMENT}" \
  --resource-group "$RG" \
  --query id --output tsv)

az monitor autoscale create \
  --resource-group "$RG" \
  --resource "$PLAN_ID" \
  --resource-type Microsoft.Web/serverfarms \
  --name "autoscale-${APP_NAME}" \
  --min-count 2 \
  --max-count 10 \
  --count 2

az monitor autoscale rule create \
  --resource-group "$RG" \
  --autoscale-name "autoscale-${APP_NAME}" \
  --condition "Percentage CPU > 70 avg 5m" \
  --scale out 2

az monitor autoscale rule create \
  --resource-group "$RG" \
  --autoscale-name "autoscale-${APP_NAME}" \
  --condition "Percentage CPU < 30 avg 10m" \
  --scale in 1

# ── Azure Front Door ──────────────────────────────────────────────────────────
echo "🌍 Creating Azure Front Door..."
az afd profile create \
  --profile-name "afd-${APP_NAME}-${ENVIRONMENT}" \
  --resource-group "$RG" \
  --sku Premium_AzureFrontDoor

echo ""
echo "✅ Deployment complete!"
echo "   Primary App: https://${APP_PRIMARY}.azurewebsites.net"
echo "   DR App:      https://${APP_DR}.azurewebsites.net"
echo "   Key Vault:   $KV_NAME"
echo "   SQL Server:  ${SQL_SERVER_PRIMARY}.database.windows.net"
echo ""
echo "⚠️  Next steps:"
echo "   1. Configure private endpoints for SQL and Storage"
echo "   2. Set up Front Door routing rules"
echo "   3. Configure WAF policies"
echo "   4. Deploy application code"

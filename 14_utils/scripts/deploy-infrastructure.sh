#!/bin/bash
# Azure Infrastructure Deployment Script
# Deploys complete web application infrastructure using Bicep

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
APP_NAME="${APP_NAME:-myapp}"
LOCATION="${LOCATION:-eastus}"
RG="rg-${APP_NAME}-${ENVIRONMENT}-${LOCATION}"
BICEP_FILE="${BICEP_FILE:-devops/02_bicep_iac.bicep}"
PARAMS_FILE="${PARAMS_FILE:-}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Validation ────────────────────────────────────────────────────────────────
log "Validating prerequisites..."

command -v az    >/dev/null || { err "Azure CLI not installed"; exit 1; }
command -v jq    >/dev/null || { warn "jq not installed — some features limited"; }

az account set --subscription "$SUBSCRIPTION_ID"
CURRENT_SUB=$(az account show --query name --output tsv)
log "Using subscription: $CURRENT_SUB"

if [[ "$ENVIRONMENT" == "prod" ]]; then
  warn "Deploying to PRODUCTION environment!"
  read -p "Are you sure? (yes/no): " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { log "Deployment cancelled"; exit 0; }
fi

# ── Resource Group ────────────────────────────────────────────────────────────
log "Creating resource group: $RG"
az group create \
  --name "$RG" \
  --location "$LOCATION" \
  --tags \
    Environment="$ENVIRONMENT" \
    Application="$APP_NAME" \
    DeployedBy="$(az account show --query user.name --output tsv)" \
    DeployedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --output none

# ── Generate SQL Password ─────────────────────────────────────────────────────
SQL_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
SQL_PASSWORD="${SQL_PASSWORD}Aa1!"  # Ensure complexity requirements

# ── Validate Template ─────────────────────────────────────────────────────────
log "Validating Bicep template..."
VALIDATE_RESULT=$(az deployment group validate \
  --resource-group "$RG" \
  --template-file "$BICEP_FILE" \
  --parameters \
    environment="$ENVIRONMENT" \
    appName="$APP_NAME" \
    sqlAdminPassword="$SQL_PASSWORD" \
    acrLoginServer="${ACR_LOGIN_SERVER:-myregistry.azurecr.io}" \
  --output json 2>&1)

if echo "$VALIDATE_RESULT" | grep -q '"error"'; then
  err "Template validation failed:"
  echo "$VALIDATE_RESULT" | jq '.error' 2>/dev/null || echo "$VALIDATE_RESULT"
  exit 1
fi
log "Template validation passed ✓"

# ── What-If Preview ───────────────────────────────────────────────────────────
log "Running what-if analysis..."
az deployment group what-if \
  --resource-group "$RG" \
  --template-file "$BICEP_FILE" \
  --parameters \
    environment="$ENVIRONMENT" \
    appName="$APP_NAME" \
    sqlAdminPassword="$SQL_PASSWORD" \
    acrLoginServer="${ACR_LOGIN_SERVER:-myregistry.azurecr.io}" \
  --result-format FullResourcePayloads 2>/dev/null || true

if [[ "$ENVIRONMENT" == "prod" ]]; then
  read -p "Review what-if output. Proceed with deployment? (yes/no): " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { log "Deployment cancelled"; exit 0; }
fi

# ── Deploy ────────────────────────────────────────────────────────────────────
DEPLOYMENT_NAME="deploy-${APP_NAME}-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"
log "Starting deployment: $DEPLOYMENT_NAME"

DEPLOY_OUTPUT=$(az deployment group create \
  --resource-group "$RG" \
  --template-file "$BICEP_FILE" \
  --name "$DEPLOYMENT_NAME" \
  --parameters \
    environment="$ENVIRONMENT" \
    appName="$APP_NAME" \
    sqlAdminPassword="$SQL_PASSWORD" \
    acrLoginServer="${ACR_LOGIN_SERVER:-myregistry.azurecr.io}" \
  --output json)

if [ $? -ne 0 ]; then
  err "Deployment failed!"
  az deployment group show \
    --resource-group "$RG" \
    --name "$DEPLOYMENT_NAME" \
    --query "properties.error" \
    --output json
  exit 1
fi

# ── Extract Outputs ───────────────────────────────────────────────────────────
log "Extracting deployment outputs..."
WEB_APP_URL=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.webAppUrl.value // "N/A"')
KV_NAME=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.keyVaultName.value // "N/A"')
SQL_FQDN=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.sqlServerFqdn.value // "N/A"')
STORAGE_NAME=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.storageAccountName.value // "N/A"')

# Store SQL password in Key Vault
if [[ "$KV_NAME" != "N/A" ]]; then
  log "Storing SQL password in Key Vault..."
  az keyvault secret set \
    --vault-name "$KV_NAME" \
    --name "SqlAdminPassword" \
    --value "$SQL_PASSWORD" \
    --output none
fi

# ── Health Check ──────────────────────────────────────────────────────────────
if [[ "$WEB_APP_URL" != "N/A" ]]; then
  log "Waiting for app to start..."
  sleep 30
  for i in {1..10}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${WEB_APP_URL}/health" 2>/dev/null || echo "000")
    if [[ "$STATUS" == "200" ]]; then
      log "Health check passed ✓"
      break
    fi
    warn "Health check attempt $i: HTTP $STATUS"
    sleep 15
  done
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
log "✅ Deployment Complete!"
echo "════════════════════════════════════════════════════════"
echo "  Environment:    $ENVIRONMENT"
echo "  Resource Group: $RG"
echo "  Deployment:     $DEPLOYMENT_NAME"
echo ""
echo "  Resources:"
echo "  🌐 Web App:     $WEB_APP_URL"
echo "  🔐 Key Vault:   $KV_NAME"
echo "  🗄️  SQL Server:  $SQL_FQDN"
echo "  💾 Storage:     $STORAGE_NAME"
echo "════════════════════════════════════════════════════════"

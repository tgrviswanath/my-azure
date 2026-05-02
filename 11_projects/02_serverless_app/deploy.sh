#!/bin/bash
# Project 02 — Serverless App Deployment
set -euo pipefail

RG="rg-serverless-prod-eastus"
LOCATION="eastus"
FUNC_APP="func-orders-prod-$(openssl rand -hex 4)"
STORAGE_NAME="stfuncprod$(openssl rand -hex 4)"
COSMOS_NAME="cosmos-orders-prod-$(openssl rand -hex 4)"
SB_NAMESPACE="sbns-orders-prod-$(openssl rand -hex 4)"
KV_NAME="kv-serverless-prod-$(openssl rand -hex 4)"
LAW_NAME="law-serverless-prod"

echo "🚀 Deploying Serverless Order Processing System"
az group create --name $RG --location $LOCATION --tags Project=Serverless Environment=prod

# Log Analytics
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name $LAW_NAME --resource-group $RG --location $LOCATION \
  --sku PerGB2018 --query id --output tsv)

# Application Insights
AI_CONN=$(az monitor app-insights component create \
  --app "ai-serverless-prod" --resource-group $RG --location $LOCATION \
  --workspace $LAW_ID --query connectionString --output tsv)

# Key Vault
az keyvault create --name $KV_NAME --resource-group $RG --location $LOCATION \
  --enable-rbac-authorization true --enable-soft-delete true --soft-delete-retention-days 7

# Storage for Function App
az storage account create --name $STORAGE_NAME --resource-group $RG \
  --location $LOCATION --sku Standard_LRS --kind StorageV2 --https-only true

# Cosmos DB (Serverless)
az cosmosdb create --name $COSMOS_NAME --resource-group $RG \
  --locations regionName=$LOCATION failoverPriority=0 \
  --default-consistency-level Session --kind GlobalDocumentDB

az cosmosdb sql database create --account-name $COSMOS_NAME \
  --resource-group $RG --name "orders-db"

az cosmosdb sql container create --account-name $COSMOS_NAME \
  --resource-group $RG --database-name "orders-db" --name "orders" \
  --partition-key-path "/customerId" --throughput 400

az cosmosdb sql container create --account-name $COSMOS_NAME \
  --resource-group $RG --database-name "orders-db" --name "leases" \
  --partition-key-path "/id" --throughput 400

# Service Bus
az servicebus namespace create --name $SB_NAMESPACE --resource-group $RG \
  --location $LOCATION --sku Standard

az servicebus queue create --name "orders-queue" \
  --namespace-name $SB_NAMESPACE --resource-group $RG \
  --max-delivery-count 10 --dead-lettering-on-message-expiration true

# Store connection strings in Key Vault
COSMOS_CONN=$(az cosmosdb keys list --name $COSMOS_NAME --resource-group $RG \
  --type connection-strings --query "connectionStrings[0].connectionString" --output tsv)
SB_CONN=$(az servicebus namespace authorization-rule keys list \
  --namespace-name $SB_NAMESPACE --resource-group $RG \
  --name RootManageSharedAccessKey --query primaryConnectionString --output tsv)

az keyvault secret set --vault-name $KV_NAME --name "CosmosDBConnection" --value "$COSMOS_CONN"
az keyvault secret set --vault-name $KV_NAME --name "ServiceBusConnection" --value "$SB_CONN"

# Function App (Consumption Plan)
az functionapp create --name $FUNC_APP --resource-group $RG \
  --storage-account $STORAGE_NAME --consumption-plan-location $LOCATION \
  --runtime node --runtime-version 18 --functions-version 4 --os-type Linux

# Enable Managed Identity
PRINCIPAL_ID=$(az functionapp identity assign --name $FUNC_APP \
  --resource-group $RG --query principalId --output tsv)

# Grant Key Vault access
KV_ID=$(az keyvault show --name $KV_NAME --resource-group $RG --query id --output tsv)
az role assignment create --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" --scope $KV_ID

# Configure app settings
az functionapp config appsettings set --name $FUNC_APP --resource-group $RG \
  --settings \
    APPLICATIONINSIGHTS_CONNECTION_STRING="$AI_CONN" \
    COSMOS_ENDPOINT="https://${COSMOS_NAME}.documents.azure.com:443/" \
    COSMOS_DATABASE="orders-db" \
    COSMOS_CONTAINER="orders" \
    CosmosDBConnection="@Microsoft.KeyVault(VaultName=${KV_NAME};SecretName=CosmosDBConnection)" \
    ServiceBusConnection="@Microsoft.KeyVault(VaultName=${KV_NAME};SecretName=ServiceBusConnection)" \
    STORAGE_ACCOUNT_NAME="$STORAGE_NAME"

# Deploy functions
cd functions
npm ci
func azure functionapp publish $FUNC_APP --javascript
cd ..

echo ""
echo "✅ Serverless deployment complete!"
echo "   Function App: https://${FUNC_APP}.azurewebsites.net"
echo "   Cosmos DB:    $COSMOS_NAME"
echo "   Service Bus:  $SB_NAMESPACE"
echo ""
echo "Test:"
echo "  curl -X POST https://${FUNC_APP}.azurewebsites.net/api/orders \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"productId\":\"123\",\"quantity\":2,\"userId\":\"user1\"}'"

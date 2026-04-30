#!/bin/bash
# Project 04 — Data Pipeline Deployment Script
# Creates Event Hubs, ADLS Gen2, Stream Analytics, and Data Factory

set -euo pipefail

RG="rg-datapipeline-prod-eastus"
LOCATION="eastus"
PREFIX="datapipeline"
EVHNS_NAME="${PREFIX}evhns$(openssl rand -hex 4)"
ADLS_NAME="${PREFIX}adls$(openssl rand -hex 4)"
SA_NAME="${PREFIX}sa$(openssl rand -hex 4)"
ADF_NAME="${PREFIX}-adf"
LAW_NAME="${PREFIX}-law"

echo "🚀 Deploying Data Pipeline Infrastructure"
az group create --name $RG --location $LOCATION --tags Project=DataPipeline Environment=prod

# ── Log Analytics ─────────────────────────────────────────────────────────────
echo "📊 Creating Log Analytics workspace..."
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name $LAW_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time 90 \
  --query id --output tsv)

# ── Event Hubs ────────────────────────────────────────────────────────────────
echo "📨 Creating Event Hubs namespace..."
az eventhubs namespace create \
  --name $EVHNS_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard \
  --capacity 4 \
  --enable-kafka true \
  --zone-redundant true

# Create event hubs for different data streams
for HUB in "telemetry" "clickstream" "transactions" "logs"; do
  echo "  Creating hub: $HUB"
  az eventhubs eventhub create \
    --name $HUB \
    --namespace-name $EVHNS_NAME \
    --resource-group $RG \
    --partition-count 4 \
    --message-retention 7
done

# Consumer groups
az eventhubs eventhub consumer-group create \
  --name "stream-analytics" \
  --eventhub-name "telemetry" \
  --namespace-name $EVHNS_NAME \
  --resource-group $RG

az eventhubs eventhub consumer-group create \
  --name "databricks" \
  --eventhub-name "telemetry" \
  --namespace-name $EVHNS_NAME \
  --resource-group $RG

# ── ADLS Gen2 (Data Lake) ─────────────────────────────────────────────────────
echo "🗄️ Creating Azure Data Lake Storage Gen2..."
az storage account create \
  --name $ADLS_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --enable-hierarchical-namespace true \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Create medallion architecture containers
for TIER in "bronze" "silver" "gold" "archive"; do
  echo "  Creating container: $TIER"
  az storage fs create \
    --name $TIER \
    --account-name $ADLS_NAME \
    --auth-mode login
done

# Create directory structure
for DIR in "telemetry/raw" "telemetry/processed" "clickstream/raw" "transactions/raw"; do
  az storage fs directory create \
    --name $DIR \
    --file-system "bronze" \
    --account-name $ADLS_NAME \
    --auth-mode login
done

# ── Storage Account (for Stream Analytics output) ─────────────────────────────
echo "💾 Creating storage account for Stream Analytics..."
az storage account create \
  --name $SA_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true

az storage container create \
  --name "stream-output" \
  --account-name $SA_NAME \
  --auth-mode login

# ── Stream Analytics ──────────────────────────────────────────────────────────
echo "⚡ Creating Stream Analytics job..."
az stream-analytics job create \
  --job-name "${PREFIX}-asa" \
  --resource-group $RG \
  --location $LOCATION \
  --output-error-policy Drop \
  --events-outoforder-policy Adjust \
  --events-outoforder-max-delay-in-seconds 5 \
  --events-late-arrival-max-delay-in-seconds 16 \
  --data-locale "en-US" \
  --compatibility-level "1.2" \
  --sku-name Standard

# Get Event Hub connection string
EVHNS_CONN=$(az eventhubs namespace authorization-rule keys list \
  --resource-group $RG \
  --namespace-name $EVHNS_NAME \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString \
  --output tsv)

# Add input
az stream-analytics input create \
  --job-name "${PREFIX}-asa" \
  --resource-group $RG \
  --input-name "telemetry-input" \
  --type Stream \
  --datasource '{
    "type": "Microsoft.ServiceBus/EventHub",
    "properties": {
      "eventHubName": "telemetry",
      "serviceBusNamespace": "'$EVHNS_NAME'",
      "sharedAccessPolicyName": "RootManageSharedAccessKey",
      "sharedAccessPolicyKey": "'$(az eventhubs namespace authorization-rule keys list --resource-group $RG --namespace-name $EVHNS_NAME --name RootManageSharedAccessKey --query primaryKey --output tsv)'",
      "consumerGroupName": "stream-analytics"
    }
  }' \
  --serialization '{"type":"Json","properties":{"encoding":"UTF8"}}'

# Add output to ADLS
az stream-analytics output create \
  --job-name "${PREFIX}-asa" \
  --resource-group $RG \
  --output-name "adls-output" \
  --datasource '{
    "type": "Microsoft.DataLake/Accounts",
    "properties": {
      "accountName": "'$ADLS_NAME'",
      "tenantId": "'$(az account show --query tenantId --output tsv)'",
      "filePathPrefix": "bronze/telemetry/processed/{date}/{time}",
      "dateFormat": "yyyy/MM/dd",
      "timeFormat": "HH"
    }
  }' \
  --serialization '{"type":"Json","properties":{"encoding":"UTF8","format":"LineSeparated"}}'

# Add transformation query
az stream-analytics transformation create \
  --job-name "${PREFIX}-asa" \
  --resource-group $RG \
  --transformation-name "main-query" \
  --streaming-units 3 \
  --saql "
    -- Real-time aggregation: 5-minute windows
    SELECT
      System.Timestamp() AS windowEnd,
      deviceId,
      AVG(temperature) AS avgTemp,
      MAX(temperature) AS maxTemp,
      MIN(temperature) AS minTemp,
      COUNT(*) AS eventCount
    INTO [adls-output]
    FROM [telemetry-input] TIMESTAMP BY eventTime
    GROUP BY deviceId, TumblingWindow(minute, 5)
  "

# ── Azure Data Factory ────────────────────────────────────────────────────────
echo "🏭 Creating Azure Data Factory..."
az datafactory create \
  --factory-name $ADF_NAME \
  --resource-group $RG \
  --location $LOCATION

# Enable managed identity
az datafactory update \
  --factory-name $ADF_NAME \
  --resource-group $RG \
  --identity '{"type":"SystemAssigned"}'

# Grant ADF access to ADLS
ADF_PRINCIPAL=$(az datafactory show \
  --factory-name $ADF_NAME \
  --resource-group $RG \
  --query "identity.principalId" \
  --output tsv)

az role assignment create \
  --assignee $ADF_PRINCIPAL \
  --role "Storage Blob Data Contributor" \
  --scope $(az storage account show --name $ADLS_NAME --resource-group $RG --query id --output tsv)

# ── Lifecycle Policy for ADLS ─────────────────────────────────────────────────
echo "♻️ Configuring lifecycle policies..."
az storage account management-policy create \
  --account-name $ADLS_NAME \
  --resource-group $RG \
  --policy '{
    "rules": [
      {
        "name": "archive-bronze",
        "enabled": true,
        "type": "Lifecycle",
        "definition": {
          "filters": {"blobTypes": ["blockBlob"], "prefixMatch": ["bronze/"]},
          "actions": {
            "baseBlob": {
              "tierToCool": {"daysAfterModificationGreaterThan": 30},
              "tierToArchive": {"daysAfterModificationGreaterThan": 90}
            }
          }
        }
      },
      {
        "name": "delete-temp",
        "enabled": true,
        "type": "Lifecycle",
        "definition": {
          "filters": {"blobTypes": ["blockBlob"], "prefixMatch": ["bronze/temp/"]},
          "actions": {
            "baseBlob": {"delete": {"daysAfterModificationGreaterThan": 7}}
          }
        }
      }
    ]
  }'

echo ""
echo "✅ Data Pipeline deployment complete!"
echo "   Event Hubs: $EVHNS_NAME"
echo "   Data Lake:  $ADLS_NAME"
echo "   Stream Analytics: ${PREFIX}-asa"
echo "   Data Factory: $ADF_NAME"
echo ""
echo "📊 Next steps:"
echo "   1. Start Stream Analytics job: az stream-analytics job start --job-name ${PREFIX}-asa --resource-group $RG"
echo "   2. Send test events to Event Hub"
echo "   3. Create ADF pipelines for batch processing"
echo "   4. Connect Power BI to Synapse/ADLS"

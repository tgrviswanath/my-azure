# Steps — Project 9.1 Azure Data Lake Storage Gen2

## Phase 1 — Create ADLS Gen2 with Hierarchical Namespace

```bash
# Set variables
RESOURCE_GROUP="rg-datalake-dev"
LOCATION="eastus"
STORAGE_ACCOUNT="adlsgen2dev$(openssl rand -hex 4)"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Create ADLS Gen2 storage account with HNS enabled
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hierarchical-namespace true \
  --access-tier Hot \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Verify HNS is enabled
az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "isHnsEnabled"
# Expected output: true

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "[0].value" -o tsv)

echo "Storage Account: $STORAGE_ACCOUNT"
echo "Storage Key: $STORAGE_KEY"
```

## Phase 2 — Create Containers (Zones)

```bash
# Create the four zone containers (filesystems in ADLS Gen2 terminology)
for CONTAINER in raw processed curated archive; do
  az storage fs create \
    --name $CONTAINER \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY
  echo "Created container: $CONTAINER"
done

# Create directory structure inside raw/
az storage fs directory create \
  --file-system raw \
  --name "orders/2024/01" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

az storage fs directory create \
  --file-system raw \
  --name "customers/2024/01" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

az storage fs directory create \
  --file-system raw \
  --name "products/2024/01" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# Create directory structure inside processed/
az storage fs directory create \
  --file-system processed \
  --name "orders/year=2024/month=01" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

az storage fs directory create \
  --file-system processed \
  --name "customers/year=2024/month=01" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# Create directory structure inside curated/
az storage fs directory create \
  --file-system curated \
  --name "daily_revenue" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

az storage fs directory create \
  --file-system curated \
  --name "customer_segments" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# List all containers
az storage fs list \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --output table
```

## Phase 3 — Set ACLs

```bash
# Create service principals for each zone
# Data ingestion SP (write to raw only)
az ad sp create-for-rbac \
  --name "sp-datalake-ingest" \
  --role "Storage Blob Data Contributor" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT/blobServices/default/containers/raw"

# Data processing SP (read raw, write processed)
az ad sp create-for-rbac \
  --name "sp-datalake-process" \
  --role "Storage Blob Data Reader" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT/blobServices/default/containers/raw"

# Get the object IDs
INGEST_OID=$(az ad sp show --id "sp-datalake-ingest" --query objectId -o tsv 2>/dev/null || \
             az ad sp list --display-name "sp-datalake-ingest" --query "[0].id" -o tsv)

PROCESS_OID=$(az ad sp show --id "sp-datalake-process" --query objectId -o tsv 2>/dev/null || \
              az ad sp list --display-name "sp-datalake-process" --query "[0].id" -o tsv)

# Set ACL on raw/ directory — ingest SP gets rwx
az storage fs access set \
  --acl "user:$INGEST_OID:rwx,default:user:$INGEST_OID:rwx" \
  --file-system raw \
  --path "/" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# Set ACL on processed/ directory — process SP gets rwx
az storage fs access set \
  --acl "user:$PROCESS_OID:rwx,default:user:$PROCESS_OID:rwx" \
  --file-system processed \
  --path "/" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# Verify ACLs
az storage fs access show \
  --file-system raw \
  --path "/" \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# Assign Storage Blob Data Reader to Synapse managed identity on curated/
SYNAPSE_MI_OID="<synapse-managed-identity-object-id>"
az role assignment create \
  --assignee $SYNAPSE_MI_OID \
  --role "Storage Blob Data Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT/blobServices/default/containers/curated"
```

## Phase 4 — Register in Purview

```bash
# Create Purview account
PURVIEW_ACCOUNT="purview-datalake-dev"

az purview account create \
  --name $PURVIEW_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku-name Standard

# Wait for provisioning
az purview account show \
  --name $PURVIEW_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "provisioningState"

# Get Purview managed identity
PURVIEW_MI=$(az purview account show \
  --name $PURVIEW_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "identity.principalId" -o tsv)

# Grant Purview MI access to ADLS Gen2
az role assignment create \
  --assignee $PURVIEW_MI \
  --role "Storage Blob Data Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

# Register ADLS Gen2 as a data source in Purview (via REST API)
PURVIEW_ENDPOINT="https://$PURVIEW_ACCOUNT.purview.azure.com"
TOKEN=$(az account get-access-token --resource "https://purview.azure.net" --query accessToken -o tsv)

curl -X PUT "$PURVIEW_ENDPOINT/scan/datasources/adls-datalake-dev?api-version=2022-02-01-preview" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "AdlsGen2",
    "properties": {
      "endpoint": "https://'"$STORAGE_ACCOUNT"'.dfs.core.windows.net/",
      "resourceGroup": "'"$RESOURCE_GROUP"'",
      "subscriptionId": "'"$SUBSCRIPTION_ID"'",
      "location": "'"$LOCATION"'"
    }
  }'

# Create and run a scan
curl -X PUT "$PURVIEW_ENDPOINT/scan/datasources/adls-datalake-dev/scans/scan-all-zones?api-version=2022-02-01-preview" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "AdlsGen2Msi",
    "properties": {
      "scanRulesetName": "AdlsGen2",
      "scanRulesetType": "System"
    }
  }'

# Trigger the scan
curl -X POST "$PURVIEW_ENDPOINT/scan/datasources/adls-datalake-dev/scans/scan-all-zones/runs/run-$(date +%Y%m%d)?api-version=2022-02-01-preview" \
  -H "Authorization: Bearer $TOKEN"
```

## Phase 5 — Query with Synapse

```bash
# Create Synapse workspace
SYNAPSE_WORKSPACE="synapse-datalake-dev"
SYNAPSE_ADMIN_USER="sqladmin"
SYNAPSE_ADMIN_PASS="P@ssw0rd$(openssl rand -hex 4)!"

az synapse workspace create \
  --name $SYNAPSE_WORKSPACE \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --storage-account $STORAGE_ACCOUNT \
  --file-system "curated" \
  --sql-admin-login-user $SYNAPSE_ADMIN_USER \
  --sql-admin-login-password $SYNAPSE_ADMIN_PASS

# Allow your IP to access Synapse
MY_IP=$(curl -s https://api.ipify.org)
az synapse workspace firewall-rule create \
  --name "AllowMyIP" \
  --workspace-name $SYNAPSE_WORKSPACE \
  --resource-group $RESOURCE_GROUP \
  --start-ip-address $MY_IP \
  --end-ip-address $MY_IP

# Open Synapse Studio and run serverless SQL query
# In Synapse Studio → Develop → New SQL Script:
# SELECT TOP 10 *
# FROM OPENROWSET(
#     BULK 'https://<storage>.dfs.core.windows.net/curated/daily_revenue/*.parquet',
#     FORMAT = 'PARQUET'
# ) AS [result]

# Query raw CSV files
echo "Run this in Synapse Studio Serverless SQL:"
cat << 'EOF'
SELECT
    order_id,
    customer_id,
    CAST(amount AS FLOAT) AS amount,
    order_date
FROM OPENROWSET(
    BULK 'https://STORAGE_ACCOUNT.dfs.core.windows.net/raw/orders/2024/01/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE,
    PARSER_VERSION = '2.0'
) WITH (
    order_id    VARCHAR(50),
    customer_id VARCHAR(50),
    amount      VARCHAR(20),
    order_date  VARCHAR(20)
) AS orders
WHERE CAST(amount AS FLOAT) > 100
ORDER BY order_date DESC;
EOF

echo "Data Lake setup complete!"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Purview Account: $PURVIEW_ACCOUNT"
echo "Synapse Workspace: $SYNAPSE_WORKSPACE"
```

# Lab 03 — Configure Storage and Access

## Objective
Create a storage account with blob containers, configure lifecycle policies, generate SAS tokens, and set up private endpoints.

## Step 1: Create Storage Account

```bash
RG="rg-lab03-dev-eastus"
LOCATION="eastus"
STORAGE_NAME="stlab03$(openssl rand -hex 4)"

az group create --name $RG --location $LOCATION

az storage account create \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --access-tier Hot \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --enable-hierarchical-namespace false

# Get storage key
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --query "[0].value" \
  --output tsv)

echo "Storage Account: $STORAGE_NAME"
```

## Step 2: Create Containers and Upload Files

```bash
# Create containers
for CONTAINER in uploads images documents archive; do
  az storage container create \
    --name $CONTAINER \
    --account-name $STORAGE_NAME \
    --auth-mode login
  echo "Created container: $CONTAINER"
done

# Create test files
echo "Hello, Azure Storage!" > test.txt
echo '{"id":1,"name":"test"}' > data.json
dd if=/dev/urandom bs=1024 count=100 > large-file.bin 2>/dev/null

# Upload files
az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name uploads \
  --name "test.txt" \
  --file test.txt \
  --tier Hot \
  --auth-mode login

az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name documents \
  --name "data.json" \
  --file data.json \
  --content-type "application/json" \
  --auth-mode login

# Upload with metadata
az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name uploads \
  --name "large-file.bin" \
  --file large-file.bin \
  --metadata "uploaded_by=lab03" "environment=dev" \
  --auth-mode login

# List blobs
az storage blob list \
  --account-name $STORAGE_NAME \
  --container-name uploads \
  --output table \
  --auth-mode login
```

## Step 3: Configure Lifecycle Management

```bash
# Create lifecycle policy
cat > lifecycle-policy.json << 'EOF'
{
  "rules": [
    {
      "name": "moveToCoool",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["uploads/"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": { "daysAfterModificationGreaterThan": 30 },
            "tierToArchive": { "daysAfterModificationGreaterThan": 90 },
            "delete": { "daysAfterModificationGreaterThan": 365 }
          },
          "snapshot": {
            "delete": { "daysAfterCreationGreaterThan": 90 }
          }
        }
      }
    },
    {
      "name": "deleteOldDocuments",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["documents/temp/"]
        },
        "actions": {
          "baseBlob": {
            "delete": { "daysAfterModificationGreaterThan": 7 }
          }
        }
      }
    }
  ]
}
EOF

az storage account management-policy create \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --policy @lifecycle-policy.json

echo "Lifecycle policy applied"
```

## Step 4: Generate SAS Tokens

```bash
# Account SAS (broad access — avoid in production)
ACCOUNT_SAS=$(az storage account generate-sas \
  --account-name $STORAGE_NAME \
  --permissions rl \
  --resource-types sco \
  --services b \
  --expiry $(date -u -d "1 hour" +%Y-%m-%dT%H:%MZ) \
  --https-only \
  --output tsv)

echo "Account SAS: ?$ACCOUNT_SAS"

# Service SAS (specific container)
CONTAINER_SAS=$(az storage container generate-sas \
  --account-name $STORAGE_NAME \
  --name uploads \
  --permissions rl \
  --expiry $(date -u -d "1 hour" +%Y-%m-%dT%H:%MZ) \
  --https-only \
  --auth-mode login \
  --as-user \
  --output tsv)

echo "Container SAS: ?$CONTAINER_SAS"

# Blob SAS (specific file)
BLOB_SAS=$(az storage blob generate-sas \
  --account-name $STORAGE_NAME \
  --container-name uploads \
  --name test.txt \
  --permissions r \
  --expiry $(date -u -d "1 hour" +%Y-%m-%dT%H:%MZ) \
  --https-only \
  --auth-mode login \
  --as-user \
  --output tsv)

BLOB_URL="https://${STORAGE_NAME}.blob.core.windows.net/uploads/test.txt?${BLOB_SAS}"
echo "Blob URL with SAS: $BLOB_URL"

# Test access
curl "$BLOB_URL"
```

## Step 5: Enable Soft Delete and Versioning

```bash
# Enable blob soft delete (7 days)
az storage account blob-service-properties update \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --enable-delete-retention true \
  --delete-retention-days 7 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 7 \
  --enable-versioning true \
  --enable-change-feed true

# Test soft delete
az storage blob delete \
  --account-name $STORAGE_NAME \
  --container-name uploads \
  --name test.txt \
  --auth-mode login

# List deleted blobs
az storage blob list \
  --account-name $STORAGE_NAME \
  --container-name uploads \
  --include d \
  --auth-mode login \
  --output table

# Restore deleted blob
az storage blob undelete \
  --account-name $STORAGE_NAME \
  --container-name uploads \
  --name test.txt \
  --auth-mode login

echo "Blob restored!"
```

## Step 6: Configure Storage Firewall

```bash
# Create VNet for private access
az network vnet create \
  --name vnet-lab03 \
  --resource-group $RG \
  --address-prefix 10.0.0.0/16

az network vnet subnet create \
  --name snet-app \
  --resource-group $RG \
  --vnet-name vnet-lab03 \
  --address-prefix 10.0.1.0/24 \
  --service-endpoints Microsoft.Storage

# Enable firewall — deny all, allow specific VNet
az storage account update \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --default-action Deny \
  --bypass AzureServices

# Allow specific VNet
az storage account network-rule add \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --vnet-name vnet-lab03 \
  --subnet snet-app

# Allow your current IP (for testing)
MY_IP=$(curl -s https://api.ipify.org)
az storage account network-rule add \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --ip-address $MY_IP

echo "Firewall configured. Only VNet and $MY_IP can access storage."

# Verify
az storage account show \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --query "networkRuleSet" \
  --output json
```

## Cleanup

```bash
az group delete --name $RG --yes --no-wait
```

## Expected Outcomes
- ✅ Storage account with ZRS redundancy
- ✅ Multiple containers with blobs
- ✅ Lifecycle policy moving data through tiers
- ✅ SAS tokens for time-limited access
- ✅ Soft delete protecting against accidental deletion
- ✅ Firewall restricting access to VNet + specific IPs

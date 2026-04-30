# Azure Storage — Blob, File, Queue, Table & Lifecycle

## Storage Account Types

```
StorageV2 (General Purpose v2) — recommended for most scenarios
├── Blob: Hot, Cool, Cold, Archive tiers
├── File: SMB/NFS shares
├── Queue: Message queuing
├── Table: NoSQL key-value
└── Data Lake Storage Gen2 (hierarchical namespace)

Premium Block Blobs — low latency, high throughput
Premium File Shares — high-performance SMB/NFS
Premium Page Blobs — VHD disks for VMs

Redundancy Options:
  LRS  (Locally Redundant):    3 copies in 1 datacenter, cheapest
  ZRS  (Zone Redundant):       3 copies across 3 zones, recommended
  GRS  (Geo Redundant):        LRS + async replication to paired region
  GZRS (Geo-Zone Redundant):   ZRS + async replication to paired region
  RA-GRS / RA-GZRS:            Read access to secondary region
```

## Blob Storage

```bash
# Create storage account
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

# Create container
az storage container create \
  --name images \
  --account-name $STORAGE_NAME \
  --auth-mode login

# Upload with tier
az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name images \
  --name "photo.jpg" \
  --file ./photo.jpg \
  --tier Hot

# Generate SAS token (time-limited access)
az storage blob generate-sas \
  --account-name $STORAGE_NAME \
  --container-name images \
  --name photo.jpg \
  --permissions r \
  --expiry $(date -u -d "1 hour" +%Y-%m-%dT%H:%MZ) \
  --auth-mode login \
  --as-user \
  --output tsv

# Copy between accounts
az storage blob copy start \
  --destination-account-name $DEST_STORAGE \
  --destination-container backup \
  --destination-blob photo.jpg \
  --source-account-name $STORAGE_NAME \
  --source-container images \
  --source-blob photo.jpg
```

## Storage Tiers & Lifecycle

```
Hot:     Frequent access, highest storage cost, lowest access cost
Cool:    Infrequent access (30+ days), lower storage, higher access
Cold:    Rare access (90+ days), even lower storage, higher access
Archive: Offline storage (180+ days), lowest storage, highest access + rehydration time

Rehydration from Archive: Standard (15h) or High Priority (1h)
```

```json
// Lifecycle management policy (ARM/JSON)
{
  "rules": [
    {
      "name": "moveToCoool",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["logs/"]
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
    }
  ]
}
```

```bash
# Apply lifecycle policy
az storage account management-policy create \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --policy @lifecycle-policy.json
```

## Shared Access Signatures (SAS)

```
SAS Types:
  Account SAS:   Access to multiple services/resources
  Service SAS:   Access to specific service (blob, file, queue, table)
  User Delegation SAS: Uses Azure AD credentials (most secure)

SAS Components:
  sv: version
  ss: services (b=blob, f=file, q=queue, t=table)
  srt: resource types (s=service, c=container, o=object)
  sp: permissions (r=read, w=write, d=delete, l=list, a=add, c=create)
  se: expiry time
  sip: allowed IP range
  spr: allowed protocols (https only recommended)
  sig: signature
```

## Azure Files

```bash
# Create file share
az storage share create \
  --name myshare \
  --account-name $STORAGE_NAME \
  --quota 100  # GB

# Mount on Linux
sudo mount -t cifs //$STORAGE_NAME.file.core.windows.net/myshare /mnt/myshare \
  -o vers=3.0,username=$STORAGE_NAME,password=$STORAGE_KEY,dir_mode=0777,file_mode=0777

# Mount on Windows
net use Z: \\$STORAGE_NAME.file.core.windows.net\myshare /u:$STORAGE_NAME $STORAGE_KEY
```

## Queue Storage

```bash
# Create queue
az storage queue create \
  --name orders \
  --account-name $STORAGE_NAME

# Send message
az storage message put \
  --queue-name orders \
  --account-name $STORAGE_NAME \
  --content '{"orderId":"123","amount":99.99}'

# Peek (don't remove)
az storage message peek \
  --queue-name orders \
  --account-name $STORAGE_NAME

# Get and process (removes from queue)
az storage message get \
  --queue-name orders \
  --account-name $STORAGE_NAME
```

## Interview Questions

### Q1: What is the difference between LRS, ZRS, GRS, and GZRS?
**Answer:**
- **LRS**: 3 copies in 1 datacenter. Cheapest. Protects against drive/rack failure. Not zone/region resilient.
- **ZRS**: 3 copies across 3 availability zones. Protects against datacenter failure. Recommended for most production.
- **GRS**: LRS + async replication to paired region. Protects against region failure. Secondary not readable by default.
- **GZRS**: ZRS + async replication to paired region. Best protection. Use for critical data.
- **RA-GRS/RA-GZRS**: Same as GRS/GZRS but secondary region is readable (for DR reads).

### Q2: When would you use Archive tier vs Cool tier?
**Answer:**
- **Cool**: Data accessed occasionally (monthly), must be available within milliseconds. 30-day minimum storage. Examples: backups, older logs.
- **Archive**: Data rarely accessed, can tolerate hours of rehydration delay. 180-day minimum. Examples: compliance archives, raw data backups.
- **Cost**: Archive is cheapest to store but most expensive to access and requires rehydration (up to 15 hours standard, 1 hour high priority).

### Q3: What is a SAS token and what are the security best practices?
**Answer:**
SAS (Shared Access Signature) provides delegated access to storage resources without sharing account keys. Best practices:
1. Use **User Delegation SAS** (Azure AD-based) over account SAS
2. Set **minimum permissions** needed
3. Set **short expiry** times
4. Restrict to **HTTPS only**
5. Restrict to **specific IP ranges** when possible
6. Use **stored access policies** for revocable SAS
7. Never embed SAS in client-side code — generate server-side

### Q4: How do you secure a storage account?
**Answer:**
1. Disable public blob access (`--allow-blob-public-access false`)
2. Enforce HTTPS only (`--https-only true`)
3. Set minimum TLS version to 1.2
4. Use private endpoints (no public internet access)
5. Enable firewall — allow only specific VNets/IPs
6. Use Azure AD authentication (not account keys)
7. Rotate account keys regularly or use Managed Identity
8. Enable soft delete for blobs and containers
9. Enable versioning for critical data
10. Enable diagnostic logging

# Azure Coding Challenges & Practical Exercises

## Challenge 1: Deploy a Resilient Web App (Bicep)

**Task**: Write a Bicep template that deploys:
- App Service (P1v3, Linux, Node.js 18)
- Azure SQL Database (General Purpose, 2 vCores)
- Key Vault with the SQL connection string
- Managed Identity with Key Vault Secrets User role
- Application Insights

**Solution outline**:
```bicep
// Key components needed:
// 1. Log Analytics workspace (for App Insights)
// 2. Application Insights (linked to workspace)
// 3. Key Vault (RBAC-enabled)
// 4. SQL Server + Database
// 5. App Service Plan (Linux, P1v3)
// 6. Web App (SystemAssigned identity)
// 7. Role assignment: Web App → Key Vault Secrets User
// 8. Key Vault secret: SQL connection string

// Critical: use uniqueString() for globally unique names
// Critical: dependsOn is auto-detected via resourceId() references
// Critical: securestring for SQL password parameter
```

---

## Challenge 2: Write a KQL Query

**Task**: Write a KQL query that finds the top 5 slowest API endpoints in the last hour, showing P50, P95, P99 response times and error rate.

**Solution**:
```kusto
requests
| where timestamp > ago(1h)
| summarize
    requestCount = count(),
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99),
    errorRate = round(countif(success == false) * 100.0 / count(), 2)
  by name
| where requestCount > 10  // filter out noise
| order by p95 desc
| take 5
| project
    Endpoint = name,
    Requests = requestCount,
    ['P50 (ms)'] = round(p50, 0),
    ['P95 (ms)'] = round(p95, 0),
    ['P99 (ms)'] = round(p99, 0),
    ['Error %'] = errorRate
```

---

## Challenge 3: Azure CLI Script

**Task**: Write a bash script that:
1. Creates a storage account
2. Creates 3 containers (raw, processed, archive)
3. Uploads a file to raw
4. Generates a SAS token valid for 1 hour
5. Verifies the file is accessible via SAS URL

**Solution**:
```bash
#!/bin/bash
set -euo pipefail

RG="rg-challenge3"
LOCATION="eastus"
STORAGE_NAME="stchallenge3$(openssl rand -hex 4)"

# Create resource group and storage
az group create --name $RG --location $LOCATION --output none
az storage account create \
  --name $STORAGE_NAME --resource-group $RG \
  --location $LOCATION --sku Standard_LRS \
  --https-only true --min-tls-version TLS1_2 \
  --allow-blob-public-access false --output none

# Create containers
for CONTAINER in raw processed archive; do
  az storage container create \
    --name $CONTAINER --account-name $STORAGE_NAME \
    --auth-mode login --output none
  echo "Created container: $CONTAINER"
done

# Create and upload test file
echo "Hello, Azure Storage!" > test.txt
az storage blob upload \
  --account-name $STORAGE_NAME --container-name raw \
  --name "test.txt" --file test.txt \
  --auth-mode login --output none
echo "Uploaded test.txt to raw container"

# Generate SAS token (1 hour)
EXPIRY=$(date -u -d "1 hour" +%Y-%m-%dT%H:%MZ 2>/dev/null || \
         date -u -v+1H +%Y-%m-%dT%H:%MZ)

SAS=$(az storage blob generate-sas \
  --account-name $STORAGE_NAME \
  --container-name raw --name test.txt \
  --permissions r --expiry $EXPIRY \
  --https-only --auth-mode login --as-user \
  --output tsv)

SAS_URL="https://${STORAGE_NAME}.blob.core.windows.net/raw/test.txt?${SAS}"
echo "SAS URL: $SAS_URL"

# Verify access
CONTENT=$(curl -s "$SAS_URL")
echo "File content: $CONTENT"
[ "$CONTENT" == "Hello, Azure Storage!" ] && echo "✅ Verification passed!" || echo "❌ Verification failed"

# Cleanup
rm test.txt
az group delete --name $RG --yes --no-wait
```

---

## Challenge 4: Terraform Module

**Task**: Write a Terraform module that creates an Azure Function App with:
- Consumption plan
- Storage account
- Application Insights
- Managed Identity
- Key Vault access

**Solution**:
```hcl
# modules/function-app/main.tf
variable "name"                { type = string }
variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "runtime"             { type = string; default = "node" }
variable "runtime_version"     { type = string; default = "18" }
variable "key_vault_id"        { type = string; default = "" }
variable "app_settings"        { type = map(string); default = {} }
variable "tags"                { type = map(string); default = {} }

resource "random_string" "suffix" {
  length = 6; special = false; upper = false
}

resource "azurerm_storage_account" "func" {
  name                     = "st${replace(var.name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  https_traffic_only_enabled = true
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_service_plan" "func" {
  name                = "asp-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption
  tags                = var.tags
}

resource "azurerm_linux_function_app" "func" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.func.id
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key
  https_only                 = true
  tags                       = var.tags

  identity { type = "SystemAssigned" }

  site_config {
    application_stack {
      node_version = var.runtime == "node" ? var.runtime_version : null
    }
  }

  app_settings = var.app_settings
}

resource "azurerm_role_assignment" "kv_secrets" {
  count                = var.key_vault_id != "" ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.func.identity[0].principal_id
}

output "id"           { value = azurerm_linux_function_app.func.id }
output "name"         { value = azurerm_linux_function_app.func.name }
output "hostname"     { value = azurerm_linux_function_app.func.default_hostname }
output "principal_id" { value = azurerm_linux_function_app.func.identity[0].principal_id }
```

---

## Challenge 5: Design a Highly Available Architecture

**Task**: Design an Azure architecture for a financial application requiring:
- 99.99% availability
- < 100ms response time globally
- PCI-DSS compliance
- Zero data loss (RPO = 0)
- RTO < 5 minutes

**Solution**:
```
Architecture:

Global Layer:
  Azure Front Door Premium (WAF, anycast routing, health probes)
  ↓
Regional Layer (East US + West Europe, Active-Active):
  Application Gateway v2 (WAF, SSL termination)
  ↓
  App Service Premium P3v3 (zone-redundant, 3 instances min)
  ↓
Data Layer:
  Azure SQL Business Critical (zone-redundant, auto-failover group)
  - Synchronous replication within region (RPO = 0)
  - Async replication to DR region (RPO < 5s)
  Azure Cache for Redis Premium (zone-redundant, geo-replication)

Security:
  Private Endpoints for all PaaS services
  Azure Firewall Premium (IDPS, TLS inspection)
  Key Vault (HSM-backed, CMK for data encryption)
  Managed Identity (no credentials)
  Conditional Access + PIM for admin access
  Microsoft Defender for Cloud (all plans)

Compliance:
  Azure Policy (PCI-DSS initiative)
  Immutable storage for audit logs
  Microsoft Purview (data classification)
  Log Analytics (90-day retention)

Monitoring:
  Application Insights (distributed tracing)
  Azure Monitor (metrics, alerts)
  Microsoft Sentinel (SIEM)

Key decisions:
  - Business Critical SQL: synchronous replicas = RPO 0 within region
  - Failover group: automatic failover < 5 min = RTO < 5 min
  - Zone-redundant: protects against datacenter failure
  - Active-Active: no cold start on failover
  - Front Door: routes to healthy region automatically
```

---

## Challenge 6: Troubleshoot a Failing Deployment

**Task**: A Bicep deployment fails with: `"The subscription is not registered to use namespace 'Microsoft.Insights'"`

**Solution**:
```bash
# Register the resource provider
az provider register --namespace Microsoft.Insights --wait

# Check registration status
az provider show --namespace Microsoft.Insights --query "registrationState"

# List all unregistered providers needed for common services
PROVIDERS=(
  "Microsoft.Insights"
  "Microsoft.OperationalInsights"
  "Microsoft.KeyVault"
  "Microsoft.ContainerService"
  "Microsoft.ContainerRegistry"
  "Microsoft.Sql"
  "Microsoft.DocumentDB"
  "Microsoft.Cache"
  "Microsoft.ServiceBus"
  "Microsoft.EventHub"
  "Microsoft.Web"
  "Microsoft.Storage"
  "Microsoft.Network"
  "Microsoft.Compute"
)

for PROVIDER in "${PROVIDERS[@]}"; do
  STATE=$(az provider show --namespace $PROVIDER --query "registrationState" --output tsv 2>/dev/null || echo "NotFound")
  if [ "$STATE" != "Registered" ]; then
    echo "Registering: $PROVIDER"
    az provider register --namespace $PROVIDER --wait
  fi
done
```

---

## Challenge 7: Cost Optimization Script

**Task**: Write a script that identifies and reports on Azure cost-saving opportunities.

**Solution**: See `utils/scripts/cost-optimization.sh` for the complete implementation.

Key areas to check:
1. Stopped (not deallocated) VMs
2. Orphaned managed disks
3. Unused public IP addresses
4. Empty resource groups
5. Old snapshots (> 30 days)
6. App Service Plans with no apps
7. Azure Advisor recommendations

---

## Quick Reference: Common Azure CLI Patterns

```bash
# Get resource ID
az resource show --resource-group $RG --name $NAME \
  --resource-type "Microsoft.Web/sites" --query id --output tsv

# Wait for operation
az vm wait --resource-group $RG --name $VM --created

# Query with JMESPath
az vm list --query "[?location=='eastus'].{Name:name,Size:hardwareProfile.vmSize}" --output table

# Loop over resources
az resource list --resource-group $RG --query "[].name" --output tsv | while read NAME; do
  echo "Processing: $NAME"
done

# Pipe to jq
az webapp show --name $APP --resource-group $RG | jq '.siteConfig.appSettings'

# Set multiple app settings from file
az webapp config appsettings set --name $APP --resource-group $RG \
  --settings @appsettings.json

# Get secret from Key Vault
SECRET=$(az keyvault secret show --vault-name $KV --name MySecret --query value --output tsv)

# Check if resource exists
if az resource show --ids $RESOURCE_ID &>/dev/null; then
  echo "Resource exists"
fi
```

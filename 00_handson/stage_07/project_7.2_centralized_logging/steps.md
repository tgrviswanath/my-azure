# Steps — Project 7.2 Centralized Logging

## Phase 1 — Create Log Analytics Workspace

```bash
# Create resource group
az group create \
  --name rg-logging-demo \
  --location eastus \
  --tags project=7.2 environment=demo

# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --resource-group rg-logging-demo \
  --workspace-name law-logging-demo \
  --location eastus \
  --sku PerGB2018 \
  --retention-time 30

# Get workspace details
LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-logging-demo \
  --workspace-name law-logging-demo \
  --query id --output tsv)

LAW_CUSTOMER_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-logging-demo \
  --workspace-name law-logging-demo \
  --query customerId --output tsv)

echo "Workspace ID: $LAW_ID"
echo "Customer ID: $LAW_CUSTOMER_ID"

# Enable Activity Log collection (subscription-level)
az monitor log-analytics workspace data-export create \
  --resource-group rg-logging-demo \
  --workspace-name law-logging-demo \
  --name export-activity-logs \
  --tables AzureActivity \
  --enable true

# Verify workspace
az monitor log-analytics workspace list \
  --resource-group rg-logging-demo \
  --output table
```

## Phase 2 — Configure Diagnostic Settings

```bash
# Create a VM to collect logs from
az vm create \
  --resource-group rg-logging-demo \
  --name vm-logging-demo \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys

VM_ID=$(az vm show \
  --resource-group rg-logging-demo \
  --name vm-logging-demo \
  --query id --output tsv)

# Enable diagnostic settings on VM
az monitor diagnostic-settings create \
  --name diag-vm-logging \
  --resource $VM_ID \
  --workspace $LAW_ID \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# Create storage account and enable diagnostics
az storage account create \
  --name stloggingdemo$RANDOM \
  --resource-group rg-logging-demo \
  --location eastus \
  --sku Standard_LRS

STORAGE_ID=$(az storage account list \
  --resource-group rg-logging-demo \
  --query "[0].id" --output tsv)

az monitor diagnostic-settings create \
  --name diag-storage-logging \
  --resource "${STORAGE_ID}/blobServices/default" \
  --workspace $LAW_ID \
  --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' \
  --metrics '[{"category":"Transaction","enabled":true}]'

# Enable Activity Log → Log Analytics
az monitor log-profiles create \
  --name default \
  --location eastus \
  --locations global eastus westus \
  --categories Write Delete Action \
  --days 30 \
  --enabled true \
  --workspace-id $LAW_ID 2>/dev/null || \
az monitor activity-log alert create \
  --resource-group rg-logging-demo \
  --name activity-log-collection \
  --scopes "/subscriptions/$(az account show --query id --output tsv)" \
  --condition category=Administrative

# Verify diagnostic settings
az monitor diagnostic-settings list \
  --resource $VM_ID \
  --output table
```

## Phase 3 — Deploy Managed Grafana

```bash
# Register Grafana provider
az provider register --namespace Microsoft.Dashboard

# Create Managed Grafana instance
az grafana create \
  --name grafana-logging-demo \
  --resource-group rg-logging-demo \
  --location eastus \
  --sku Standard

# Wait for provisioning (takes 2-3 minutes)
az grafana show \
  --name grafana-logging-demo \
  --resource-group rg-logging-demo \
  --query "properties.endpoint" \
  --output tsv

# Get Grafana endpoint
GRAFANA_URL=$(az grafana show \
  --name grafana-logging-demo \
  --resource-group rg-logging-demo \
  --query "properties.endpoint" \
  --output tsv)

echo "Grafana URL: $GRAFANA_URL"

# Assign yourself as Grafana Admin
USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)

az role assignment create \
  --assignee $USER_OBJECT_ID \
  --role "Grafana Admin" \
  --scope $(az grafana show \
    --name grafana-logging-demo \
    --resource-group rg-logging-demo \
    --query id --output tsv)

# Verify Grafana is running
az grafana show \
  --name grafana-logging-demo \
  --resource-group rg-logging-demo \
  --query "{name:name, endpoint:properties.endpoint, state:properties.provisioningState}" \
  --output json
```

## Phase 4 — Connect Grafana to Log Analytics

```bash
# Azure Managed Grafana auto-configures Azure Monitor data source
# Verify the data source is available via Grafana API
GRAFANA_URL=$(az grafana show \
  --name grafana-logging-demo \
  --resource-group rg-logging-demo \
  --query "properties.endpoint" --output tsv)

# Get Grafana API token
GRAFANA_TOKEN=$(az grafana api-key create \
  --name grafana-logging-demo \
  --resource-group rg-logging-demo \
  --key-name "terraform-key" \
  --role Admin \
  --query key --output tsv)

# List data sources (Azure Monitor should be pre-configured)
curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "${GRAFANA_URL}/api/datasources" | python3 -m json.tool

# Add Log Analytics workspace as explicit data source
curl -s -X POST \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  "${GRAFANA_URL}/api/datasources" \
  -d "{
    \"name\": \"Azure Monitor - law-logging-demo\",
    \"type\": \"grafana-azure-monitor-datasource\",
    \"access\": \"proxy\",
    \"jsonData\": {
      \"subscriptionId\": \"$(az account show --query id --output tsv)\",
      \"logAnalyticsDefaultWorkspace\": \"$LAW_CUSTOMER_ID\"
    }
  }"

# Test data source connectivity
curl -s -X POST \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "${GRAFANA_URL}/api/datasources/1/health" | python3 -m json.tool
```

## Phase 5 — Create Dashboard

```bash
# Import Azure Monitor overview dashboard (ID: 10956 from grafana.com)
curl -s -X POST \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  "${GRAFANA_URL}/api/dashboards/import" \
  -d '{
    "dashboard": {
      "id": null,
      "title": "Azure Resource Logs Overview",
      "tags": ["azure", "logging"],
      "timezone": "browser",
      "panels": [
        {
          "id": 1,
          "title": "Log Ingestion Rate",
          "type": "timeseries",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "targets": [
            {
              "datasource": {"type": "grafana-azure-monitor-datasource"},
              "queryType": "Azure Log Analytics",
              "azureLogAnalytics": {
                "query": "union * | summarize count() by bin(TimeGenerated, 5m), Type | order by TimeGenerated desc",
                "resultFormat": "time_series"
              }
            }
          ]
        },
        {
          "id": 2,
          "title": "Top Log Sources",
          "type": "piechart",
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "targets": [
            {
              "datasource": {"type": "grafana-azure-monitor-datasource"},
              "queryType": "Azure Log Analytics",
              "azureLogAnalytics": {
                "query": "union * | summarize count() by Type | order by count_ desc | take 10",
                "resultFormat": "table"
              }
            }
          ]
        }
      ],
      "schemaVersion": 38,
      "version": 1
    },
    "overwrite": true,
    "folderId": 0
  }'

# Run log shipper to populate custom logs
cd ../code
python log_shipper.py

# Query custom logs in Log Analytics (after ~5 min ingestion delay)
az monitor log-analytics query \
  --workspace $LAW_CUSTOMER_ID \
  --analytics-query "
    AppLogs_CL
    | where TimeGenerated > ago(1h)
    | project TimeGenerated, level_s, message_s, service_s, request_id_s
    | order by TimeGenerated desc
    | take 20
  " \
  --output table

# Query log volume by type
az monitor log-analytics query \
  --workspace $LAW_CUSTOMER_ID \
  --analytics-query "
    union *
    | where TimeGenerated > ago(1h)
    | summarize count() by Type
    | order by count_ desc
  " \
  --output table

# Clean up
az group delete --name rg-logging-demo --yes --no-wait
```

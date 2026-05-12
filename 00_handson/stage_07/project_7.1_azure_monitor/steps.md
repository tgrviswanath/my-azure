# Steps — Project 7.1 Azure Monitor

## Phase 1 — Create Log Analytics Workspace

```bash
# Create resource group
az group create \
  --name rg-monitor-demo \
  --location eastus \
  --tags project=7.1 environment=demo

# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --resource-group rg-monitor-demo \
  --workspace-name law-monitor-demo \
  --location eastus \
  --sku PerGB2018 \
  --retention-time 30

# Get workspace ID and key (needed for agent config)
az monitor log-analytics workspace show \
  --resource-group rg-monitor-demo \
  --workspace-name law-monitor-demo \
  --query "{id:id, customerId:customerId}" \
  --output json

# Get workspace primary key
az monitor log-analytics workspace get-shared-keys \
  --resource-group rg-monitor-demo \
  --workspace-name law-monitor-demo \
  --output json

# Verify workspace created
az monitor log-analytics workspace list \
  --resource-group rg-monitor-demo \
  --output table
```

## Phase 2 — Enable Diagnostics on VM

```bash
# Create a VM to monitor
az vm create \
  --resource-group rg-monitor-demo \
  --name vm-monitor-demo \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

# Get VM resource ID
VM_ID=$(az vm show \
  --resource-group rg-monitor-demo \
  --name vm-monitor-demo \
  --query id --output tsv)

echo "VM ID: $VM_ID"

# Get Log Analytics workspace resource ID
LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-monitor-demo \
  --workspace-name law-monitor-demo \
  --query id --output tsv)

# Enable diagnostic settings on VM (send metrics to Log Analytics)
az monitor diagnostic-settings create \
  --name diag-vm-monitor-demo \
  --resource $VM_ID \
  --workspace $LAW_ID \
  --metrics '[{"category":"AllMetrics","enabled":true,"retentionPolicy":{"days":30,"enabled":true}}]'

# Install Azure Monitor Agent on VM
az vm extension set \
  --resource-group rg-monitor-demo \
  --vm-name vm-monitor-demo \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --version 1.0 \
  --enable-auto-upgrade true

# Verify extension installed
az vm extension list \
  --resource-group rg-monitor-demo \
  --vm-name vm-monitor-demo \
  --output table

# Check metrics are flowing (wait 5 minutes after enabling)
az monitor metrics list \
  --resource $VM_ID \
  --metric "Percentage CPU" \
  --interval PT1M \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --output table
```

## Phase 3 — Create CPU Alert Rule

```bash
# Get VM resource ID
VM_ID=$(az vm show \
  --resource-group rg-monitor-demo \
  --name vm-monitor-demo \
  --query id --output tsv)

# Create action group first (email notification)
az monitor action-group create \
  --resource-group rg-monitor-demo \
  --name ag-monitor-demo \
  --short-name agmonitor \
  --action email admin-email admin@example.com

# Add SMS to action group
az monitor action-group update \
  --resource-group rg-monitor-demo \
  --name ag-monitor-demo \
  --add-action sms admin-sms 1 5551234567

# Get action group resource ID
AG_ID=$(az monitor action-group show \
  --resource-group rg-monitor-demo \
  --name ag-monitor-demo \
  --query id --output tsv)

# Create CPU alert rule (fires when CPU > 80% for 5 minutes)
az monitor metrics alert create \
  --name alert-cpu-high \
  --resource-group rg-monitor-demo \
  --scopes $VM_ID \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action $AG_ID \
  --description "Alert when VM CPU exceeds 80% for 5 minutes" \
  --severity 2

# Create memory alert rule (requires AMA + DCR for memory metrics)
az monitor metrics alert create \
  --name alert-disk-high \
  --resource-group rg-monitor-demo \
  --scopes $VM_ID \
  --condition "avg "OS Disk Read Bytes/sec" > 50000000" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action $AG_ID \
  --description "Alert when disk read throughput is high" \
  --severity 3

# List all alert rules
az monitor metrics alert list \
  --resource-group rg-monitor-demo \
  --output table

# Show alert rule details
az monitor metrics alert show \
  --resource-group rg-monitor-demo \
  --name alert-cpu-high \
  --output json
```

## Phase 4 — Create Dashboard

```bash
# Export dashboard JSON template
cat > /tmp/dashboard.json << 'EOF'
{
  "lenses": {
    "0": {
      "order": 0,
      "parts": {
        "0": {
          "position": {"x": 0, "y": 0, "colSpan": 6, "rowSpan": 4},
          "metadata": {
            "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart",
            "settings": {
              "content": {
                "options": {
                  "chart": {
                    "metrics": [
                      {
                        "resourceMetadata": {"id": "/subscriptions/{sub}/resourceGroups/rg-monitor-demo/providers/Microsoft.Compute/virtualMachines/vm-monitor-demo"},
                        "name": "Percentage CPU",
                        "aggregationType": 4,
                        "namespace": "microsoft.compute/virtualmachines",
                        "metricVisualization": {"displayName": "CPU %"}
                      }
                    ],
                    "title": "VM CPU Percentage",
                    "titleKind": 1,
                    "visualization": {"chartType": 2}
                  }
                }
              }
            }
          }
        }
      }
    }
  },
  "metadata": {
    "model": {
      "timeRange": {
        "value": {"relative": {"duration": 24, "timeUnit": 1}},
        "type": "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
      }
    }
  }
}
EOF

# Create dashboard via Azure CLI
az portal dashboard create \
  --resource-group rg-monitor-demo \
  --name dashboard-monitor-demo \
  --input-path /tmp/dashboard.json \
  --location eastus

# Alternative: create via REST API
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
az rest \
  --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-monitor-demo/providers/Microsoft.Portal/dashboards/dashboard-monitor-demo?api-version=2020-09-01-preview" \
  --body @/tmp/dashboard.json

# List dashboards
az portal dashboard list \
  --resource-group rg-monitor-demo \
  --output table
```

## Phase 5 — Test Alert

```bash
# Install stress tool on VM and trigger CPU spike
az vm run-command invoke \
  --resource-group rg-monitor-demo \
  --name vm-monitor-demo \
  --command-id RunShellScript \
  --scripts "sudo apt-get install -y stress && stress --cpu 4 --timeout 360 &"

# Watch metrics in real time (poll every 30 seconds)
VM_ID=$(az vm show --resource-group rg-monitor-demo --name vm-monitor-demo --query id --output tsv)

for i in {1..10}; do
  echo "=== Poll $i at $(date) ==="
  az monitor metrics list \
    --resource $VM_ID \
    --metric "Percentage CPU" \
    --interval PT1M \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --output table
  sleep 30
done

# Check if alert fired
az monitor activity-log list \
  --resource-group rg-monitor-demo \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --query "[?contains(operationName.value, 'microsoft.insights/alertrules')]" \
  --output table

# List fired alerts
az monitor metrics alert list \
  --resource-group rg-monitor-demo \
  --output json | python3 -c "
import json, sys
alerts = json.load(sys.stdin)
for a in alerts:
    print(f\"Alert: {a['name']} | Enabled: {a['enabled']} | Severity: {a['severity']}\")
"

# Stop stress test
az vm run-command invoke \
  --resource-group rg-monitor-demo \
  --name vm-monitor-demo \
  --command-id RunShellScript \
  --scripts "pkill stress || true"

# Clean up resources
az group delete --name rg-monitor-demo --yes --no-wait
```

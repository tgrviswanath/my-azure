# Steps — Project 7.4 Log Analytics Query Lab

## Phase 1 — Enable NSG Flow Logs

```bash
# Create Network Watcher (if not exists)
az network watcher configure \
  --resource-group NetworkWatcherRG \
  --locations eastus \
  --enabled true

# Enable NSG flow logs
az network watcher flow-log create \
  --resource-group rg-log-analytics \
  --name nsg-flow-log \
  --nsg my-nsg \
  --storage-account mystorageaccount \
  --workspace /subscriptions/<sub>/resourceGroups/rg-log-analytics/providers/Microsoft.OperationalInsights/workspaces/law-handson \
  --enabled true \
  --format JSON \
  --log-version 2
```

---

## Phase 2 — Enable Activity Log Collection

```bash
# Create diagnostic setting to send Activity Log to Log Analytics
az monitor diagnostic-settings create \
  --name "activity-to-law" \
  --resource /subscriptions/<subscription-id> \
  --workspace /subscriptions/<sub>/resourceGroups/rg-log-analytics/providers/Microsoft.OperationalInsights/workspaces/law-handson \
  --logs '[{"category":"Administrative","enabled":true},{"category":"Security","enabled":true},{"category":"Alert","enabled":true}]'
```

---

## Phase 3 — Run KQL Queries

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-log-analytics \
  --workspace-name law-handson \
  --query customerId -o tsv)

# Top 10 operations in last 24 hours
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureActivity | where TimeGenerated > ago(24h) | summarize count() by OperationNameValue | top 10 by count_"

# Failed operations
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureActivity | where ActivityStatusValue == 'Failure' | project TimeGenerated, Caller, OperationNameValue, ResourceGroup"
```

---

## Phase 4 — Save Queries in Portal

```
1. Azure Portal → Log Analytics → Logs
2. Write your KQL query
3. Click Save → Save as query
4. Add to query pack for team sharing
```

---

## Phase 5 — Create Alert from Query

```bash
az monitor scheduled-query create \
  --resource-group rg-log-analytics \
  --name "failed-deployments-alert" \
  --scopes /subscriptions/<sub>/resourceGroups/rg-log-analytics/providers/Microsoft.OperationalInsights/workspaces/law-handson \
  --condition "count 'AzureActivity | where ActivityStatusValue == \"Failure\" and OperationNameValue contains \"deployments\"' greater than 5" \
  --condition-query "AzureActivity | where ActivityStatusValue == 'Failure'" \
  --evaluation-frequency PT5M \
  --window-size PT15M \
  --severity 2
```

---

## Screenshots to Take
- [ ] KQL query returning NSG flow data
- [ ] Activity log showing role assignment changes
- [ ] Saved query in query pack
- [ ] Alert rule created from KQL query

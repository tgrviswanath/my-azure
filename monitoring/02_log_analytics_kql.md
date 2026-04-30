# Azure Monitoring — Advanced KQL & Dashboards

## KQL Advanced Queries

```kusto
// ── Performance Analysis ──────────────────────────────────────────────────────

// P50/P95/P99 response times by endpoint (last 1 hour)
requests
| where timestamp > ago(1h)
| summarize
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99),
    count = count(),
    errorRate = countif(success == false) * 100.0 / count()
  by name
| order by p95 desc
| take 20

// Dependency performance (external calls)
dependencies
| where timestamp > ago(1h)
| summarize
    avgDuration = avg(duration),
    p95 = percentile(duration, 95),
    failureRate = countif(success == false) * 100.0 / count(),
    callCount = count()
  by target, name, type
| where callCount > 10
| order by avgDuration desc

// Error trend over time
requests
| where timestamp > ago(24h)
| where success == false
| summarize errorCount = count() by bin(timestamp, 5m), resultCode
| render timechart

// ── Security Analysis ─────────────────────────────────────────────────────────

// Failed login attempts by user and IP
SigninLogs
| where TimeGenerated > ago(24h)
| where ResultType != "0"
| summarize
    failedAttempts = count(),
    distinctIPs = dcount(IPAddress),
    locations = make_set(Location)
  by UserPrincipalName
| where failedAttempts > 5
| order by failedAttempts desc

// Impossible travel detection
SigninLogs
| where TimeGenerated > ago(24h)
| where ResultType == "0"
| project UserPrincipalName, TimeGenerated, Location, IPAddress, Latitude, Longitude
| sort by UserPrincipalName, TimeGenerated asc
| extend prevTime = prev(TimeGenerated), prevLocation = prev(Location), prevUser = prev(UserPrincipalName)
| where UserPrincipalName == prevUser
| extend timeDiff = datetime_diff('minute', TimeGenerated, prevTime)
| where timeDiff < 60 and Location != prevLocation
| project UserPrincipalName, TimeGenerated, Location, prevLocation, timeDiff

// Privileged operations audit
AzureActivity
| where TimeGenerated > ago(7d)
| where OperationNameValue in ("Microsoft.Authorization/roleAssignments/write",
                                "Microsoft.KeyVault/vaults/secrets/write",
                                "Microsoft.Compute/virtualMachines/delete")
| where ActivityStatusValue == "Success"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, Resource
| order by TimeGenerated desc

// ── Cost Analysis ─────────────────────────────────────────────────────────────

// Resource creation/deletion activity
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue endswith "/write" or OperationNameValue endswith "/delete"
| where ActivityStatusValue == "Success"
| summarize count() by ResourceProviderValue, bin(TimeGenerated, 1d)
| render timechart

// ── Infrastructure Health ─────────────────────────────────────────────────────

// VM CPU utilization heatmap
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize avgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
| render heatmap

// Disk space alerts
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
| where InstanceName != "_Total" and InstanceName != "HarddiskVolume1"
| summarize freeSpace = avg(CounterValue) by Computer, InstanceName
| where freeSpace < 20
| project Computer, InstanceName, freeSpace = round(freeSpace, 1)
| order by freeSpace asc

// Container (AKS) pod restarts
KubePodInventory
| where TimeGenerated > ago(1h)
| where Namespace == "production"
| summarize restarts = sum(PodRestartCount) by Name, Namespace, ContainerName
| where restarts > 0
| order by restarts desc

// ── Application Health ────────────────────────────────────────────────────────

// Availability by endpoint (last 24h)
requests
| where timestamp > ago(24h)
| summarize
    total = count(),
    successful = countif(success == true),
    availability = round(countif(success == true) * 100.0 / count(), 2)
  by name
| order by availability asc

// Exception analysis with stack traces
exceptions
| where timestamp > ago(24h)
| summarize
    count = count(),
    sample = any(details)
  by type, outerMessage
| order by count desc
| take 10

// User journey funnel
customEvents
| where timestamp > ago(7d)
| where name in ("PageView", "AddToCart", "Checkout", "OrderComplete")
| summarize users = dcount(user_Id) by name
| order by users desc

// ── Alerting Queries ──────────────────────────────────────────────────────────

// High error rate alert (use in scheduled query alert)
let threshold = 5.0;
requests
| where timestamp > ago(5m)
| summarize
    total = count(),
    errors = countif(success == false)
| extend errorRate = errors * 100.0 / total
| where errorRate > threshold

// Slow response alert
requests
| where timestamp > ago(5m)
| summarize p95 = percentile(duration, 95)
| where p95 > 2000  // > 2 seconds
```

## Azure Monitor Workbooks

```json
// Workbook template (ARM JSON)
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Application Health Dashboard\n\nReal-time monitoring for production application."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "requests | where timestamp > ago(1h) | summarize count() by bin(timestamp, 5m) | render timechart",
        "size": 0,
        "title": "Request Rate (last 1h)",
        "timeContext": { "durationMs": 3600000 },
        "queryType": 0,
        "resourceType": "microsoft.insights/components"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "requests | where timestamp > ago(1h) | summarize errorRate = countif(success==false)*100.0/count() by bin(timestamp, 5m) | render timechart",
        "size": 0,
        "title": "Error Rate % (last 1h)",
        "queryType": 0,
        "resourceType": "microsoft.insights/components"
      }
    }
  ]
}
```

## Diagnostic Settings — All Resources

```bash
# Enable diagnostics for all resources in a resource group
az resource list --resource-group $RG --query "[].id" --output tsv | while read RESOURCE_ID; do
  RESOURCE_TYPE=$(az resource show --ids "$RESOURCE_ID" --query type --output tsv)

  # Get available log categories
  CATEGORIES=$(az monitor diagnostic-settings categories list \
    --resource "$RESOURCE_ID" \
    --query "value[?categoryType=='Logs'].name" \
    --output tsv 2>/dev/null)

  if [ -n "$CATEGORIES" ]; then
    LOGS_JSON="["
    for CAT in $CATEGORIES; do
      LOGS_JSON+="{\"category\":\"$CAT\",\"enabled\":true},"
    done
    LOGS_JSON="${LOGS_JSON%,}]"

    az monitor diagnostic-settings create \
      --name "diag-to-law" \
      --resource "$RESOURCE_ID" \
      --workspace "$LAW_ID" \
      --logs "$LOGS_JSON" \
      --metrics '[{"category":"AllMetrics","enabled":true}]' \
      2>/dev/null && echo "Enabled diagnostics for $RESOURCE_ID"
  fi
done
```

## Interview Questions

### Q1: What is the difference between Azure Monitor Metrics and Logs?
**Answer:**
- **Metrics**: Numerical time-series, collected every minute, 93-day retention, near real-time, lightweight. Best for dashboards and threshold alerts. Examples: CPU%, request count, response time.
- **Logs**: Structured records queryable with KQL, configurable retention (30-730 days), richer data. Best for troubleshooting, complex queries, log-based alerts. Examples: HTTP logs, exception details, audit events.

### Q2: How do you set up end-to-end distributed tracing?
**Answer:**
1. Enable Application Insights on all services
2. Use the same Instrumentation Key / Connection String
3. Pass correlation headers (traceparent) between services
4. Use SDK's `startOperation` / `trackDependency` for custom spans
5. View in Application Insights → Application Map (shows service dependencies)
6. Use Transaction Search to trace a single request across services

### Q3: What is a Log Analytics workspace and how do you design it?
**Answer:**
Log Analytics workspace is the central store for Azure Monitor Logs. Design considerations:
- **Single workspace**: simpler, cross-resource queries, lower cost
- **Multiple workspaces**: data sovereignty, different retention, access isolation
- **Retention**: 30-730 days (default 30), archive tier for longer
- **Cost**: charged per GB ingested + retention beyond 31 days
- **Access**: workspace-level or resource-level RBAC
Recommendation: one workspace per environment (dev/prod), or one per region for compliance.

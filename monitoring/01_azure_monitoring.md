# Azure Monitoring — Monitor, Log Analytics & Application Insights

## Azure Monitor Architecture

```
Azure Monitor
├── Metrics (numerical, time-series, 93 days retention)
│   ├── Platform metrics: auto-collected from Azure resources
│   └── Custom metrics: from apps, agents
├── Logs (structured, queryable via KQL)
│   ├── Activity Log: subscription-level events
│   ├── Resource Logs: resource-level diagnostics
│   └── Log Analytics Workspace: central log store
├── Alerts
│   ├── Metric alerts: threshold-based
│   ├── Log alerts: KQL query-based
│   └── Activity log alerts: subscription events
└── Insights
    ├── Application Insights: APM for apps
    ├── VM Insights: VM performance + dependencies
    ├── Container Insights: AKS monitoring
    └── Network Insights: network topology
```

## Log Analytics & KQL

```bash
# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --workspace-name law-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time 90

# Enable diagnostic settings for App Service
az monitor diagnostic-settings create \
  --name diag-webapp \
  --resource $WEBAPP_ID \
  --workspace $LAW_ID \
  --logs '[{"category":"AppServiceHTTPLogs","enabled":true},{"category":"AppServiceConsoleLogs","enabled":true},{"category":"AppServiceAppLogs","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

```kusto
// KQL — Kusto Query Language Examples

// HTTP errors in last 24 hours
AppServiceHTTPLogs
| where TimeGenerated > ago(24h)
| where ScStatus >= 400
| summarize count() by ScStatus, CsUriStem
| order by count_ desc
| take 20

// Average response time by endpoint
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| summarize avg(TimeTaken), percentile(TimeTaken, 95), percentile(TimeTaken, 99)
    by CsUriStem
| order by avg_TimeTaken desc

// Failed requests with details
requests
| where success == false
| where timestamp > ago(1h)
| project timestamp, name, url, resultCode, duration, customDimensions
| order by timestamp desc

// Exception analysis
exceptions
| where timestamp > ago(24h)
| summarize count() by type, outerMessage
| order by count_ desc

// Dependency failures (external calls)
dependencies
| where success == false
| where timestamp > ago(1h)
| summarize count() by target, name, resultCode
| order by count_ desc

// Performance: slow requests
requests
| where timestamp > ago(1h)
| where duration > 2000  // > 2 seconds
| project timestamp, name, duration, url, customDimensions
| order by duration desc

// VM CPU usage
Perf
| where ObjectName == "Processor"
| where CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
| render timechart

// Security: failed login attempts
SigninLogs
| where ResultType != "0"  // non-success
| where TimeGenerated > ago(24h)
| summarize count() by UserPrincipalName, IPAddress, ResultDescription
| order by count_ desc

// Cost analysis
AzureActivity
| where OperationNameValue contains "write" or OperationNameValue contains "delete"
| where ActivityStatusValue == "Success"
| summarize count() by ResourceProviderValue, OperationNameValue
| order by count_ desc
```

## Application Insights

```javascript
// Node.js Application Insights setup
const appInsights = require('applicationinsights');

appInsights.setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING)
  .setAutoDependencyCorrelation(true)
  .setAutoCollectRequests(true)
  .setAutoCollectPerformance(true)
  .setAutoCollectExceptions(true)
  .setAutoCollectDependencies(true)
  .setAutoCollectConsole(true)
  .setUseDiskRetryCaching(true)
  .setSendLiveMetrics(true)
  .start();

const client = appInsights.defaultClient;

// Custom events
client.trackEvent({
  name: 'OrderPlaced',
  properties: {
    orderId: order.id,
    amount: order.total,
    userId: user.id,
    region: 'eastus',
  },
  measurements: {
    itemCount: order.items.length,
    processingTimeMs: elapsed,
  }
});

// Custom metrics
client.trackMetric({
  name: 'QueueDepth',
  value: queueLength,
});

// Custom exceptions
try {
  await processOrder(order);
} catch (err) {
  client.trackException({
    exception: err,
    properties: { orderId: order.id, userId: user.id },
    severityLevel: appInsights.Contracts.SeverityLevel.Error,
  });
  throw err;
}

// Custom dependencies (external calls)
const startTime = Date.now();
try {
  const result = await externalApi.call(data);
  client.trackDependency({
    target: 'external-api.example.com',
    name: 'POST /process',
    data: JSON.stringify(data),
    duration: Date.now() - startTime,
    resultCode: 200,
    success: true,
    dependencyTypeName: 'HTTP',
  });
  return result;
} catch (err) {
  client.trackDependency({
    target: 'external-api.example.com',
    name: 'POST /process',
    duration: Date.now() - startTime,
    resultCode: err.status || 500,
    success: false,
    dependencyTypeName: 'HTTP',
  });
  throw err;
}
```

## Alerts

```bash
# Metric alert: CPU > 80%
az monitor metrics alert create \
  --name "HighCPU-${APP_NAME}" \
  --resource-group $RG \
  --scopes $WEBAPP_ID \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action $ACTION_GROUP_ID \
  --description "CPU usage exceeded 80% for 5 minutes"

# Log alert: error rate > 5%
az monitor scheduled-query create \
  --name "HighErrorRate-${APP_NAME}" \
  --resource-group $RG \
  --scopes $LAW_ID \
  --condition-query "requests | where timestamp > ago(5m) | summarize errorRate = countif(success == false) * 100.0 / count() | where errorRate > 5" \
  --condition-time-aggregation Count \
  --condition-operator GreaterThan \
  --condition-threshold 0 \
  --evaluation-frequency 5m \
  --window-size 5m \
  --severity 1 \
  --action $ACTION_GROUP_ID

# Create action group (email + webhook)
az monitor action-group create \
  --name ag-oncall \
  --resource-group $RG \
  --short-name oncall \
  --email-receiver name=oncall email=oncall@company.com \
  --webhook-receiver name=pagerduty service-uri=https://events.pagerduty.com/...
```

## Interview Questions

### Q1: What is the difference between Azure Monitor Metrics and Logs?
**Answer:**
- **Metrics**: Numerical time-series data, collected every minute, 93-day retention, near real-time, lightweight. Best for dashboards and threshold alerts.
- **Logs**: Structured records (JSON), queryable with KQL, configurable retention (30-730 days), richer data. Best for troubleshooting, complex queries, log-based alerts.

### Q2: What is Application Insights and what does it automatically collect?
**Answer:**
Application Insights is an APM (Application Performance Monitoring) service. Auto-collects:
- HTTP requests (URL, duration, status code)
- Dependencies (SQL, HTTP, Redis calls)
- Exceptions and stack traces
- Performance counters (CPU, memory)
- Custom events and metrics (via SDK)
- User sessions and page views (browser SDK)
- Live Metrics Stream (real-time)

### Q3: What is KQL and give an example of a useful query?
**Answer:**
KQL (Kusto Query Language) is used to query Azure Monitor Logs. Example — find top 5 slowest API endpoints:
```kusto
requests
| where timestamp > ago(1h)
| summarize avg(duration), percentile(duration, 95) by name
| order by avg_duration desc
| take 5
```

### Q4: How do you set up alerting for a production application?
**Answer:**
1. **Availability**: ping test every 5 min from multiple locations
2. **Error rate**: alert if > 1% requests fail
3. **Response time**: alert if P95 > 2 seconds
4. **CPU/Memory**: alert if > 80% for 5+ minutes
5. **Custom business metrics**: order failures, payment errors
6. **Action groups**: email + PagerDuty/Slack webhook
7. **Severity levels**: Sev0 (critical) → Sev4 (informational)

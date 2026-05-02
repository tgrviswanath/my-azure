# Lab 08 — Azure Monitor: Alerts, Dashboards & Log Analytics

## Objective
Set up comprehensive monitoring for a web application: configure diagnostic settings, create metric and log alerts, build a KQL dashboard, and set up Application Insights.

## Prerequisites
- Azure CLI installed and logged in
- An existing App Service or VM to monitor (or create one)
- Estimated time: 45 minutes
- Estimated cost: ~$0.00 (basic monitoring is free)

---

## Step 1: Create Log Analytics Workspace

```bash
RG="rg-lab08-monitoring-dev"
LOCATION="eastus"
LAW_NAME="law-lab08-monitoring"
APP_NAME="app-lab08-$RANDOM"

az group create --name $RG --location $LOCATION

# Create Log Analytics Workspace
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name $LAW_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time 30 \
  --query id --output tsv)

echo "Log Analytics Workspace: $LAW_ID"
```

---

## Step 2: Create App Service with Application Insights

```bash
# Create App Service Plan
az appservice plan create \
  --name asp-lab08 \
  --resource-group $RG \
  --location $LOCATION \
  --sku B1 \
  --is-linux

# Create App Service
az webapp create \
  --name $APP_NAME \
  --resource-group $RG \
  --plan asp-lab08 \
  --runtime "NODE:18-lts"

# Create Application Insights
AI_KEY=$(az monitor app-insights component create \
  --app ai-lab08 \
  --resource-group $RG \
  --location $LOCATION \
  --kind web \
  --workspace $LAW_ID \
  --query instrumentationKey \
  --output tsv)

AI_CONNECTION=$(az monitor app-insights component show \
  --app ai-lab08 \
  --resource-group $RG \
  --query connectionString \
  --output tsv)

# Connect App Insights to App Service
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RG \
  --settings \
    APPINSIGHTS_INSTRUMENTATIONKEY=$AI_KEY \
    APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONNECTION \
    ApplicationInsightsAgent_EXTENSION_VERSION="~3"

echo "Application Insights connected to App Service"
```

---

## Step 3: Enable Diagnostic Settings

```bash
APP_ID=$(az webapp show \
  --name $APP_NAME \
  --resource-group $RG \
  --query id --output tsv)

# Enable all diagnostic logs → Log Analytics
az monitor diagnostic-settings create \
  --name diag-webapp-lab08 \
  --resource $APP_ID \
  --workspace $LAW_ID \
  --logs '[
    {"category": "AppServiceHTTPLogs", "enabled": true, "retentionPolicy": {"days": 30, "enabled": true}},
    {"category": "AppServiceConsoleLogs", "enabled": true, "retentionPolicy": {"days": 30, "enabled": true}},
    {"category": "AppServiceAppLogs", "enabled": true, "retentionPolicy": {"days": 30, "enabled": true}},
    {"category": "AppServiceAuditLogs", "enabled": true, "retentionPolicy": {"days": 30, "enabled": true}},
    {"category": "AppServiceIPSecAuditLogs", "enabled": true, "retentionPolicy": {"days": 30, "enabled": true}}
  ]' \
  --metrics '[
    {"category": "AllMetrics", "enabled": true, "retentionPolicy": {"days": 30, "enabled": true}}
  ]'

echo "Diagnostic settings enabled"
```

---

## Step 4: Create Metric Alerts

```bash
# Create Action Group (email notifications)
az monitor action-group create \
  --name ag-lab08-alerts \
  --resource-group $RG \
  --short-name lab08 \
  --email-receiver name=admin email=admin@example.com

AG_ID=$(az monitor action-group show \
  --name ag-lab08-alerts \
  --resource-group $RG \
  --query id --output tsv)

# Alert 1: HTTP 5xx errors > 5 in 5 minutes
az monitor metrics alert create \
  --name "alert-http5xx-lab08" \
  --resource-group $RG \
  --scopes $APP_ID \
  --condition "count Http5xx > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action $AG_ID \
  --description "HTTP 5xx errors exceeded threshold"

# Alert 2: Response time > 3 seconds
az monitor metrics alert create \
  --name "alert-response-time-lab08" \
  --resource-group $RG \
  --scopes $APP_ID \
  --condition "avg AverageResponseTime > 3000" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 3 \
  --action $AG_ID \
  --description "Average response time exceeded 3 seconds"

# Alert 3: CPU > 80% for 10 minutes
az monitor metrics alert create \
  --name "alert-cpu-lab08" \
  --resource-group $RG \
  --scopes $APP_ID \
  --condition "avg CpuPercentage > 80" \
  --window-size 10m \
  --evaluation-frequency 5m \
  --severity 2 \
  --action $AG_ID \
  --description "CPU utilization above 80%"

echo "Metric alerts created"
```

---

## Step 5: Create Log-Based Alert (KQL)

```bash
# Alert: Application errors in logs
az monitor scheduled-query create \
  --name "alert-app-errors-lab08" \
  --resource-group $RG \
  --scopes $LAW_ID \
  --condition-query '
    AppServiceAppLogs
    | where TimeGenerated > ago(5m)
    | where Level == "Error"
    | summarize ErrorCount = count()
    | where ErrorCount > 10
  ' \
  --condition-threshold 0 \
  --condition-operator GreaterThan \
  --condition-time-aggregation Count \
  --evaluation-frequency 5m \
  --window-duration 5m \
  --severity 2 \
  --action-groups $AG_ID \
  --description "More than 10 application errors in 5 minutes"

echo "Log alert created"
```

---

## Step 6: KQL Queries in Log Analytics

```bash
# Open Log Analytics workspace in portal
echo "Open: https://portal.azure.com/#resource$LAW_ID/logs"
echo ""
echo "Run these KQL queries:"
```

```kusto
// ── Query 1: HTTP request summary ────────────────────────────────────────────
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| summarize
    TotalRequests = count(),
    Errors = countif(ScStatus >= 500),
    ErrorRate = round(countif(ScStatus >= 500) * 100.0 / count(), 2),
    AvgTimeTaken = avg(TimeTaken),
    P95TimeTaken = percentile(TimeTaken, 95)
  by bin(TimeGenerated, 5m)
| order by TimeGenerated desc

// ── Query 2: Top slow endpoints ───────────────────────────────────────────────
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| where TimeTaken > 1000  // > 1 second
| summarize
    Count = count(),
    AvgMs = avg(TimeTaken),
    P99Ms = percentile(TimeTaken, 99)
  by CsUriStem
| order by AvgMs desc
| take 10

// ── Query 3: Error analysis ───────────────────────────────────────────────────
AppServiceHTTPLogs
| where TimeGenerated > ago(24h)
| where ScStatus >= 400
| summarize Count = count() by ScStatus, CsUriStem
| order by Count desc

// ── Query 4: Application Insights — dependency failures ───────────────────────
dependencies
| where timestamp > ago(1h)
| where success == false
| summarize
    FailureCount = count(),
    AvgDuration = avg(duration)
  by target, name, type
| order by FailureCount desc

// ── Query 5: Availability over time ──────────────────────────────────────────
AppServiceHTTPLogs
| where TimeGenerated > ago(24h)
| summarize
    Total = count(),
    Successful = countif(ScStatus < 500),
    Availability = round(countif(ScStatus < 500) * 100.0 / count(), 3)
  by bin(TimeGenerated, 1h)
| order by TimeGenerated asc
| render timechart
```

---

## Step 7: Create Azure Dashboard

```bash
# Create dashboard via ARM template
cat > /tmp/dashboard.json << 'EOF'
{
  "properties": {
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
                  "options": {"chart": {"metrics": [
                    {
                      "resourceMetadata": {"id": "APP_SERVICE_ID"},
                      "name": "Http5xx",
                      "aggregationType": 1,
                      "namespace": "microsoft.web/sites",
                      "metricVisualization": {"displayName": "Http Server Errors"}
                    }
                  ]}}
                }
              }
            }
          }
        }
      }
    },
    "metadata": {
      "model": {
        "timeRange": {"value": {"relative": {"duration": 24, "timeUnit": 1}}, "type": "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"}
      }
    }
  },
  "name": "lab08-dashboard",
  "type": "Microsoft.Portal/dashboards",
  "location": "global",
  "tags": {"hidden-title": "Lab 08 Monitoring Dashboard"}
}
EOF

# Replace APP_SERVICE_ID placeholder
sed -i "s|APP_SERVICE_ID|$APP_ID|g" /tmp/dashboard.json

az portal dashboard create \
  --resource-group $RG \
  --name "lab08-dashboard" \
  --input-path /tmp/dashboard.json

echo "Dashboard created"
```

---

## Step 8: Test Alerts

```bash
# Generate some test traffic to trigger alerts
APP_URL="https://$APP_NAME.azurewebsites.net"

echo "Generating test traffic..."

# Generate 200 requests
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code}\n" $APP_URL/ &
done
wait

echo "Check Azure Monitor for alerts in 5-10 minutes"
echo "Dashboard: https://portal.azure.com/#dashboard"
```

---

## Step 9: Cleanup

```bash
az group delete --name $RG --yes --no-wait
rm -f /tmp/dashboard.json
echo "Cleanup initiated"
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| No logs appearing | Diagnostic settings not saved | Wait 5-10 min after enabling |
| Alert not firing | Threshold too high | Lower threshold for testing |
| KQL query returns nothing | Wrong table name | Check available tables in workspace |
| App Insights not collecting | Wrong connection string | Verify `APPLICATIONINSIGHTS_CONNECTION_STRING` setting |
| Action group not sending email | Email not verified | Check spam folder, verify email address |

---

## What You Learned

✅ Create Log Analytics Workspace and connect resources
✅ Enable diagnostic settings for App Service
✅ Create metric alerts with action groups
✅ Create log-based alerts using KQL
✅ Write KQL queries for performance analysis
✅ Build Azure dashboards for operational visibility
✅ Connect Application Insights for APM

# Project 7.3 — Application Insights Distributed Tracing

## What This Does

Instruments a Python Flask microservice with Application Insights to capture distributed traces, HTTP request telemetry, dependency calls, custom events, and exceptions. Demonstrates end-to-end correlation across service boundaries using operation IDs, and shows how to view traces, dependency maps, and live metrics in the Azure portal.

## Services Used

| Service | Purpose |
|---|---|
| Application Insights | Collect telemetry — requests, dependencies, exceptions, custom events |
| Log Analytics Workspace | Backend store for Application Insights data |
| Azure App Service | Host the instrumented Flask application |
| Azure Functions | Downstream service to demonstrate distributed tracing |
| Live Metrics Stream | Real-time telemetry view during load testing |

## Architecture

```
HTTP Client (browser / curl / load test)
        │
        ▼
┌───────────────────────────────────────────────────────┐
│  Flask App (app_with_tracing.py)                      │
│  Instrumented with opencensus-ext-azure               │
│                                                       │
│  Middleware: AzureExporter (auto-tracks all requests) │
│  Tracer: tracks custom spans + dependencies           │
│                                                       │
│  Routes:                                              │
│  GET /          → returns hello + logs custom event   │
│  GET /api/data  → calls downstream + tracks dep       │
│  GET /error     → raises exception (tracked)          │
│  GET /slow      → simulates slow dependency           │
└──────────────────────┬────────────────────────────────┘
                       │ (HTTPS, instrumentation key / connection string)
                       ▼
┌───────────────────────────────────────────────────────┐
│  Application Insights                                 │
│  appi-tracing-demo                                    │
│                                                       │
│  Telemetry types:                                     │
│  - requests      (HTTP in)                            │
│  - dependencies  (HTTP out, DB, queue)                │
│  - exceptions    (unhandled + tracked)                │
│  - customEvents  (business events)                    │
│  - traces        (log messages)                       │
│  - metrics       (custom gauges/counters)             │
└──────────────────────┬────────────────────────────────┘
                       │
                       ▼
┌───────────────────────────────────────────────────────┐
│  Log Analytics Workspace                              │
│  law-tracing-demo                                     │
│                                                       │
│  Tables: requests, dependencies, exceptions,          │
│          customEvents, traces, customMetrics          │
└───────────────────────────────────────────────────────┘
                       │
                       ▼
        Azure Portal — Application Map
        End-to-End Transaction Search
        Performance Blade
        Failures Blade
        Live Metrics Stream
```

## How to Run

```bash
# 1. Login and set subscription
az login
az account set --subscription "your-subscription-id"

# 2. Create resource group
az group create --name rg-tracing-demo --location eastus

# 3. Deploy infrastructure
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Get connection string
APPINSIGHTS_CONNECTION_STRING=$(terraform output -raw app_insights_connection_string)
echo "Connection string: $APPINSIGHTS_CONNECTION_STRING"

# 5. Install Python dependencies
cd ../code
pip install flask opencensus-ext-azure opencensus-ext-flask requests

# 6. Run the instrumented app locally
export APPLICATIONINSIGHTS_CONNECTION_STRING="$APPINSIGHTS_CONNECTION_STRING"
python app_with_tracing.py

# 7. Generate traffic (in another terminal)
curl http://localhost:5000/
curl http://localhost:5000/api/data
curl http://localhost:5000/error
curl http://localhost:5000/slow

# 8. Run load test
for i in {1..50}; do
  curl -s http://localhost:5000/ > /dev/null
  curl -s http://localhost:5000/api/data > /dev/null
  sleep 0.5
done

# 9. View in portal
# Portal → Application Insights → appi-tracing-demo
# → Application Map (shows service topology)
# → Transaction Search (find individual traces)
# → Performance (response times, top operations)
# → Failures (exceptions and failed requests)
# → Live Metrics (real-time while app is running)

# 10. Query telemetry with KQL
az monitor log-analytics query \
  --workspace "$(terraform output -raw law_workspace_id)" \
  --analytics-query "
    requests
    | where timestamp > ago(1h)
    | summarize count(), avg(duration) by name
    | order by count_ desc
  " \
  --output table

# 11. Create availability test
az monitor app-insights web-test create \
  --resource-group rg-tracing-demo \
  --app-insights-name appi-tracing-demo \
  --name webtest-homepage \
  --location eastus \
  --defined-web-test-kind ping \
  --request-url "https://your-app.azurewebsites.net/" \
  --frequency 300 \
  --timeout 30 \
  --enabled true

# 12. Clean up
terraform destroy
```

## Lessons Learned

- Application Insights connection strings are preferred over instrumentation keys — they include the ingestion endpoint.
- `opencensus-ext-azure` auto-instruments Flask requests via middleware — no manual span creation needed for HTTP.
- Correlation IDs (`operation_id`) link requests across services — pass them in HTTP headers for distributed tracing.
- The Application Map is built automatically from dependency tracking — no manual configuration.
- Custom events and metrics are useful for business-level telemetry (e.g., "order placed", "payment processed").
- Sampling reduces cost for high-traffic apps — configure adaptive sampling in the SDK.
- Live Metrics Stream has ~1-second latency — useful for debugging production issues in real time.
- Availability tests run from multiple Azure regions — great for detecting regional outages.

## Code

See `code/app_with_tracing.py` for the Flask application instrumented with opencensus-ext-azure, demonstrating request tracking, custom events, exception tracking, and dependency correlation.

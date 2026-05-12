# Steps — Project 7.3 Application Insights Distributed Tracing

## Phase 1 — Create Application Insights

```bash
az group create --name rg-app-insights --location eastus

az monitor app-insights component create \
  --app handson-app-insights \
  --location eastus \
  --resource-group rg-app-insights \
  --workspace /subscriptions/<sub>/resourceGroups/rg-app-insights/providers/Microsoft.OperationalInsights/workspaces/law-handson

# Get instrumentation key
az monitor app-insights component show \
  --app handson-app-insights \
  --resource-group rg-app-insights \
  --query connectionString -o tsv
```

---

## Phase 2 — Instrument Python App

```bash
pip install opencensus-ext-azure flask

export APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=xxx;IngestionEndpoint=https://eastus-8.in.applicationinsights.azure.com/"

python code/app_with_tracing.py
```

---

## Phase 3 — Generate Traffic

```bash
# In another terminal
for i in {1..20}; do
  curl http://localhost:5000/api/orders
  curl http://localhost:5000/api/users/123
  sleep 0.5
done
```

---

## Phase 4 — View Traces in Portal

```
1. Azure Portal → Application Insights → handson-app-insights
2. Investigate → Transaction search → see individual requests
3. Investigate → Application map → see service dependencies
4. Investigate → Performance → see slow operations
5. Investigate → Failures → see exceptions
```

---

## Phase 5 — Create Availability Test

```bash
az monitor app-insights web-test create \
  --web-test-name "homepage-ping" \
  --resource-group rg-app-insights \
  --app handson-app-insights \
  --location eastus \
  --defined-web-test-kind ping \
  --request-url "https://your-app.azurewebsites.net/health"
```

---

## Screenshots to Take
- [ ] Application map showing service dependencies
- [ ] End-to-end transaction trace
- [ ] Performance blade showing P95 latency
- [ ] Live Metrics stream

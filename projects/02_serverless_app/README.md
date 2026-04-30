# Project 02 — Serverless Application (Azure Functions)

## Architecture
```
HTTP Client
    ↓
API Management (rate limiting, auth, versioning)
    ↓
Azure Functions (Consumption Plan)
    ├── POST /orders → OrderFunction → Service Bus → ProcessOrderFunction
    ├── GET  /orders/{id} → GetOrderFunction → Cosmos DB
    ├── POST /upload → UploadFunction → Blob Storage
    └── Timer → CleanupFunction (daily)
         ↓
    Cosmos DB (orders)
    Blob Storage (files)
    Service Bus (async processing)
    Application Insights (monitoring)
    Key Vault (secrets)
```

## Functions
| Function | Trigger | Description |
|----------|---------|-------------|
| CreateOrder | HTTP POST | Validate and queue order |
| ProcessOrder | Service Bus | Process queued order |
| GetOrder | HTTP GET | Retrieve order by ID |
| UploadFile | HTTP POST | Upload file to blob |
| DailyCleanup | Timer (daily) | Archive old records |
| CosmosChangeFeed | Cosmos DB | React to document changes |

## Deploy
```bash
# Install Azure Functions Core Tools
npm install -g azure-functions-core-tools@4

# Create function app
az functionapp create \
  --name func-orders-prod \
  --resource-group rg-serverless-prod \
  --storage-account stfuncprod \
  --consumption-plan-location eastus \
  --runtime node \
  --runtime-version 18 \
  --functions-version 4

# Deploy
func azure functionapp publish func-orders-prod

# Test
curl -X POST https://func-orders-prod.azurewebsites.net/api/orders \
  -H "Content-Type: application/json" \
  -d '{"productId":"123","quantity":2,"userId":"user1"}'
```

## Cost Estimate
| Resource | Usage | Monthly Cost |
|----------|-------|-------------|
| Functions (Consumption) | 1M executions | ~$0.20 |
| Cosmos DB (Serverless) | 1M RU | ~$0.25 |
| Service Bus (Standard) | 1M messages | ~$0.10 |
| Storage | 10GB | ~$0.20 |
| API Management (Consumption) | 1M calls | ~$3.50 |
| **Total** | | **~$4.25/mo** |

## Scaling
- Functions auto-scale to 200 instances (Consumption)
- Cosmos DB serverless scales automatically
- Service Bus handles burst with message queuing

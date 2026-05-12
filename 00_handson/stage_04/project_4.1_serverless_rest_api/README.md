# Project 4.1 — Serverless REST API

## What This Does
Builds a REST API using Azure Functions + API Management + Cosmos DB.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Functions | Serverless compute (HTTP triggers) |
| API Management | API gateway, rate limiting, auth |
| Cosmos DB | NoSQL database |

## Architecture
```
Client → API Management → Azure Function → Cosmos DB
```

## How to Run
```bash
# Local dev
func start

# Deploy
cd terraform && terraform init && terraform apply -auto-approve
```

## Lessons Learned
- Functions scale to zero — no idle cost
- API Management adds auth, rate limiting, caching in front of Functions
- Use Cosmos DB serverless tier for dev/test (pay per request)

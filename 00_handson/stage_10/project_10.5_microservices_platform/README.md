# Project 10.5 — Production-grade Microservices Platform

## What This Does
Combines everything from the roadmap into a production-grade microservices platform. Integrates AKS, API Management, Event Hubs, Redis, Azure SQL, observability, and security into a cohesive system.

## Architecture
```
Internet
  → Azure Front Door (CDN + WAF)
    → API Management (routing, auth, rate limiting)
      ├── Order Service (AKS)
      │     ├── Azure SQL (orders DB)
      │     └── Azure Cache for Redis (cache)
      ├── User Service (AKS)
      │     └── Azure SQL (users DB)
      └── Analytics Service (AKS)
            ├── Event Hubs (event stream)
            ├── Azure Data Factory (batch processing)
            └── Synapse Analytics (analytics queries)

Observability:
  Azure Monitor + Application Insights + Managed Grafana

Security:
  WAF + Defender for Cloud + Key Vault + Managed Identity

CI/CD:
  GitHub Actions + OIDC + ACR + AKS deploy
```

## Services Used (All from Previous Projects)
| Service | Project |
|---------|---------|
| AKS | 5.4, 10.4 |
| API Management | 4.1, 4.2 |
| Event Hubs | 9.3 |
| Azure Data Factory | 9.2 |
| Synapse Analytics | 9.9 |
| Azure Cache for Redis | 5.7 |
| Azure SQL | 1.4 |
| WAF | 8.2 |
| Defender for Cloud | 8.4 |
| Key Vault | 8.1 |
| Application Insights | 7.3 |
| Managed Grafana | 7.5 |
| GitHub Actions OIDC | 6.2 |

## How to Deploy
```bash
cd terraform
terraform init
terraform apply -var-file="production.tfvars"
```

## Lessons Learned
- Start simple, add complexity gradually
- Each service owns its data — no shared databases between microservices
- Async communication (Event Hubs) decouples services
- Observability is not optional — you can't fix what you can't see
- Security is built-in, not bolted on — WAF, Key Vault, Managed Identity from day 1

## Code

### `code/platform_health.py` — Check health of all platform services

```bash
pip install azure-identity azure-mgmt-containerservice azure-mgmt-sql azure-mgmt-redis
python code/platform_health.py
```

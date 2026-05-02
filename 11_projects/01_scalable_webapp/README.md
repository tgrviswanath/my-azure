# Project 01 — Scalable Web Application

## Architecture
```
Internet → Azure Front Door (WAF + CDN)
              ↓
         App Service (auto-scale, 2 regions)
              ↓
         Azure SQL Database (Failover Group)
         Azure Redis Cache
         Azure Storage (static assets)
         Key Vault (secrets)
         Application Insights (monitoring)
```

## Components
- **Frontend**: React SPA hosted on Azure Static Web Apps
- **Backend**: Node.js API on App Service (Linux, Premium P2v3)
- **Database**: Azure SQL Database (Business Critical, zone-redundant)
- **Cache**: Azure Cache for Redis (Standard C1)
- **CDN**: Azure Front Door Premium with WAF
- **Secrets**: Key Vault with RBAC
- **Monitoring**: Application Insights + Log Analytics

## Deploy
```bash
# 1. Create infrastructure
az deployment group create \
  --resource-group rg-webapp-prod-eastus \
  --template-file infrastructure/main.bicep \
  --parameters @infrastructure/prod.parameters.json

# 2. Deploy application
az webapp deployment source config-zip \
  --name app-webapp-prod \
  --resource-group rg-webapp-prod-eastus \
  --src ./dist/app.zip

# 3. Verify
curl https://myapp.azurefd.net/health
```

## Scaling Strategy
- **Horizontal**: App Service auto-scale (2-10 instances based on CPU/HTTP queue)
- **Vertical**: Upgrade App Service Plan tier
- **Database**: Scale vCores independently, read replicas for reporting
- **Cache**: Redis cluster mode for > 53GB

## Cost Estimate (Production)
| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| App Service Plan (2 regions) | P2v3 × 2 | ~$280 |
| Azure SQL (Business Critical) | BC_Gen5_4 | ~$1,200 |
| Redis Cache | Standard C1 | ~$55 |
| Front Door | Premium | ~$335 |
| Storage | ZRS 100GB | ~$5 |
| **Total** | | **~$1,875/mo** |

## Security
- All traffic via HTTPS (Front Door enforces)
- WAF with OWASP 3.2 rules
- Private endpoints for SQL and Redis
- Managed Identity for app → Key Vault
- No public access to SQL/Redis

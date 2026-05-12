# Cost Estimate — Project 10.5 Production-grade Microservices Platform

## Summary

| Item | Monthly Cost |
|------|-------------|
| AKS Standard tier + nodes (3x D2s_v3) | ~$282 |
| API Management (Developer tier) | ~$50 |
| Event Hubs Standard (1 TU) | ~$10 |
| Azure Cache for Redis (C1) | ~$55 |
| Azure SQL (S2) | ~$75 |
| Application Insights | ~$5 |
| Managed Grafana | ~$65 |
| Key Vault | ~$1 |
| Azure Front Door | ~$35 |
| **Total** | **~$578/month** |

## Notes
- Use Developer tier for APIM in dev/test (no SLA, much cheaper)
- Production APIM: Standard tier ~$700/month
- Use spot instances for AKS user node pool: 60-80% savings
- Pause Synapse SQL Pool when not in use

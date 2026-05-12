# Cost Estimate — Project 7.5 Grafana + Prometheus Monitoring

## Summary

| Item | Monthly Cost |
|------|-------------|
| Azure Managed Prometheus (~1000 metric series) | ~$0.10 |
| Azure Managed Grafana (Essential tier) | ~$65 |
| AKS (existing cluster) | included |
| Data Collection Rules | $0 |
| **Total** | **~$65/month** |

## Notes
- Managed Prometheus: $0.10 per active metric series per month
- Managed Grafana Essential: $65/month (includes 1 admin user)
- Self-hosted Prometheus + Grafana on AKS: ~$10-20/month (node cost only)

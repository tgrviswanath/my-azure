# Cost Estimate — Project 10.4 Kubernetes on AKS

## Summary

| Item | Monthly Cost |
|------|-------------|
| AKS Standard tier (control plane) | ~$72 |
| System node pool (1x Standard_D2s_v3) | ~$70 |
| User node pool (2x Standard_D2s_v3) | ~$140 |
| Application Gateway (Standard_v2) | ~$125 |
| ACR Basic | ~$5 |
| **Total** | **~$412/month** |

## Notes
- Use spot instances for user node pool: 60-80% savings
- Scale user node pool to 0 when not in use
- AKS Free tier: no control plane cost (limited SLA)
- AKS Standard tier: $72/month for 99.95% SLA

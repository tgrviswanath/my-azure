# Cost Estimate — Project 6.5 Kubernetes GitOps with ArgoCD

## Summary

| Item | Monthly Cost |
|------|-------------|
| AKS control plane | ~$72 |
| System node pool (1x Standard_D2s_v3) | ~$70 |
| App node pool (2x Standard_D2s_v3) | ~$140 |
| ACR Basic | ~$5 |
| ArgoCD (open source) | $0 |
| **Total** | **~$287/month** |

## Notes
- Use spot instances for non-prod node pools to save 60-80%
- Scale node pool to 0 when not in use
- AKS control plane is free for dev clusters (Standard tier: $72/month)

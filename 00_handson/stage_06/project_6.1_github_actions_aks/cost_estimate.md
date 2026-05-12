# Cost Estimate — Project 6.1

## Summary

| Resource | SKU | Unit Cost | Qty | Monthly Est. |
|---|---|---|---|---|
| AKS Control Plane | Standard | $0.10/hr | 730 hrs | ~$73.00 |
| AKS Node Pool | Standard_D2s_v3 (2 nodes) | ~$0.096/hr each | 1460 hrs | ~$140.16 |
| Azure Container Registry | Basic | $0.167/day | 30 days | ~$5.00 |
| ACR Storage | Basic (10 GB included) | $0.003/GB/day | — | ~$0.00 |
| Load Balancer | Basic | ~$0.005/hr | 730 hrs | ~$3.65 |
| Public IP Address | Static | $0.004/hr | 730 hrs | ~$2.92 |
| Managed Disks (OS) | Standard SSD E10 | ~$1.92/disk | 2 disks | ~$3.84 |
| GitHub Actions | Free tier | 2000 min/month free | — | ~$0.00 |
| **Total** | | | | **~$228.57/month** |

## Notes

- **Biggest cost driver**: AKS worker nodes. Use `Standard_B2s` (~$0.042/hr) instead of `Standard_D2s_v3` to cut node costs roughly in half for dev/test.
- **Scale to zero**: AKS does not support scaling the control plane to zero. The $73/month control plane fee is fixed while the cluster exists. Delete the cluster when not in use.
- **Single node for dev**: Use a single `Standard_B2s` node for learning. Monthly node cost drops to ~$30.
- **ACR Basic**: Includes 10 GB storage and 10 webhooks. Sufficient for this project.
- **GitHub Actions free tier**: Public repos get unlimited minutes. Private repos get 2000 min/month free, then $0.008/min for Linux runners.
- **Cost optimization**: Use `az aks stop` / `az aks start` to pause the cluster overnight. Stopped clusters still incur control plane fees but node VMs are deallocated.
- All prices are approximate, based on East US region. Check [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for current rates.

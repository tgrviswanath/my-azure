# Cost Estimate — Project 1.2 Linux Web Server on Azure VM

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Azure VM | B2s (2 vCPU, 4 GB RAM) | ~$30.37 |
| OS Disk | Standard SSD 30 GB | ~$2.40 |
| Public IP | Basic Static | ~$3.00 |
| Virtual Network | Standard | $0 |
| Network Security Group | Standard | $0 |
| Bandwidth (outbound, 10 GB) | First 100 GB free | $0 |
| **Total** | | **~$35.77/month** |

## VM Size Comparison
| Size | vCPU | RAM | Monthly Cost | Use Case |
|------|------|-----|-------------|---------|
| B1s | 1 | 1 GB | ~$7.59 | Dev/test only |
| B2s | 2 | 4 GB | ~$30.37 | Light web server |
| B4ms | 4 | 16 GB | ~$121.47 | Medium workloads |
| D2s_v3 | 2 | 8 GB | ~$70.08 | Production web |

## Cost Saving Tips
- Use `az vm deallocate` when not in use — stops compute billing
- Configure auto-shutdown at 10 PM to save ~$20/month
- Use Azure Spot VMs for dev/test: up to 90% discount
- B2s Spot price: ~$3/month (vs $30 on-demand)
- Standard SSD is 2x the cost of Standard HDD — use HDD for dev

## Estimated Lab Duration
- Lab takes ~3-4 hours to complete
- Running for 4 hours only: ~$0.20 total
- Always run `terraform destroy` when done

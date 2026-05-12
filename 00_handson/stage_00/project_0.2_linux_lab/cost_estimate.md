# Cost Estimate — Project 0.2 Linux Lab on Azure VM

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Azure VM | B1s (1 vCPU, 1 GB RAM) | ~$7.59 |
| OS Disk | Standard HDD 30 GB | ~$1.20 |
| Public IP | Basic Static | ~$3.00 |
| Virtual Network | Standard | $0 |
| Network Security Group | Standard | $0 |
| Bandwidth (outbound, 5 GB) | First 100 GB free | $0 |
| **Total** | | **~$11.79/month** |

## Cost Saving Tips
- Use `az vm deallocate` when not in use — stops compute billing (disk still billed)
- B1s is the cheapest general-purpose VM — good for learning only
- Delete the Public IP when deallocated to avoid the $3/month charge
- Use Azure Spot VMs for up to 90% discount (can be evicted)

## Spot VM Alternative
```bash
# Add to Terraform for ~$0.76/month instead of $7.59
priority        = "Spot"
eviction_policy = "Deallocate"
max_bid_price   = 0.02
```

## Estimated Lab Duration
- This lab takes ~2-3 hours to complete
- If you run it for 3 hours only: ~$0.05 total cost
- Always run `terraform destroy` when done

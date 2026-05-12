# Cost Estimate — App Gateway vs Load Balancer

## Monthly Cost Breakdown

| Resource | SKU / Tier | Qty | Unit Cost | Monthly Total |
|---|---|---|---|---|
| Application Gateway | Standard_v2 (1 CU) | 1 | ~$125.00 | $125.00 |
| Azure Load Balancer | Standard | 1 | ~$18.25 | $18.25 |
| Public IP (App GW) | Standard Static | 1 | ~$3.65 | $3.65 |
| Public IP (LB) | Standard Static | 1 | ~$3.65 | $3.65 |
| VNet + Subnets | — | 1 | Free | $0.00 |
| Data processed (App GW) | per CU | ~10 GB | ~$0.008/CU-hr | ~$5.00 |
| Data processed (LB) | per GB | ~10 GB | $0.005/GB | ~$0.05 |

## Total Estimated Monthly Cost: ~$156/month

---

## Cost Comparison

| Load Balancer | Monthly Base | Per GB | Best For |
|---|---|---|---|
| Application Gateway Standard_v2 | ~$125 | ~$0.008/CU | Web apps, APIs, WAF |
| Azure Load Balancer Standard | ~$18 | ~$0.005/GB | TCP/UDP, internal services |
| Azure Load Balancer Basic | Free | Free | Dev/test only (no SLA) |

## Key Insight

Load Balancer is **7x cheaper** than Application Gateway. Use App GW only when you need L7 features (path routing, SSL termination, WAF). Use LB for everything else.

## Teardown to $0

```bash
az group delete --name rg-lb-comparison --yes --no-wait
```

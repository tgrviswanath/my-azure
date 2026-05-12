# Cost Estimate — Multi-Tier Application

## Monthly Cost Breakdown

| Resource | SKU / Tier | Qty | Unit Cost | Monthly Total |
|---|---|---|---|---|
| Application Gateway | WAF_v2 (2 capacity units) | 1 | ~$125.00 | $125.00 |
| VM Scale Set instances | Standard_B2s (2 vCPU, 4 GB) | 2 | ~$30.37/VM | $60.74 |
| Azure SQL Database | S1 (20 DTU) | 1 | ~$30.00 | $30.00 |
| Azure Front Door | Standard tier | 1 | ~$35.00 | $35.00 |
| Public IP (Standard) | Static | 1 | ~$3.65 | $3.65 |
| VNet + Subnets | — | 1 | Free | $0.00 |
| NSGs | — | 3 | Free | $0.00 |
| Outbound data transfer | ~10 GB | — | $0.087/GB | ~$0.87 |

## Total Estimated Monthly Cost: ~$255/month

---

## Cost Breakdown by Tier

| Tier | Resources | Monthly Cost |
|---|---|---|
| Network | App Gateway WAF_v2 + Public IP | ~$129 |
| Compute | VMSS 2x B2s | ~$61 |
| Database | Azure SQL S1 | ~$30 |
| CDN/Global | Azure Front Door Standard | ~$35 |

---

## Cost Optimization Tips

- **App Gateway** is the biggest cost — use Standard_v2 instead of WAF_v2 for dev/test (~$50 cheaper)
- **VMSS** — use Spot instances for non-production (up to 90% discount, but can be evicted)
- **Azure SQL** — use Basic tier (5 DTU, ~$5/month) for learning; S1 is for realistic workloads
- **Front Door** — skip for learning; add it last when testing global routing
- **Scale in aggressively** — set VMSS minimum to 1 instance during off-hours

## Teardown to $0

```bash
az group delete --name rg-multitier --yes --no-wait
```

Note: Azure Front Door profile may need to be deleted separately if it's in a different resource group.

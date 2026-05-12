# Cost Estimate — Terraform Modules (Multi-Environment)

## Per-Environment Monthly Cost

| Resource | dev | qa | prod |
|---|---|---|---|
| VM (compute) | B1s ~$7.59 | B2s ~$30.37 | D4s_v3 ~$140.16 |
| VM count | 1 | 2 | 4 |
| VM total | ~$7.59 | ~$60.74 | ~$560.64 |
| Azure SQL | Basic ~$4.99 | S1 ~$30.00 | P1 ~$465.00 |
| App Gateway | Standard_v2 ~$125 | Standard_v2 ~$125 | WAF_v2 ~$250 |
| Public IPs | ~$3.65 | ~$3.65 | ~$3.65 |
| VNet/NSG | Free | Free | Free |
| **Total** | **~$141/month** | **~$219/month** | **~$1,279/month** |

---

## Simplified Cost Tiers (Realistic Learning Setup)

For learning, use smaller sizes:

| Environment | Realistic Learning Cost |
|---|---|
| dev | ~$50/month (skip App GW, use Basic SQL) |
| qa | ~$100/month (small App GW, S1 SQL) |
| prod | ~$300/month (medium App GW, S2 SQL) |

## Cost Strategy

- **dev** — always on, smallest possible sizes, destroy at end of sprint
- **qa** — deploy for testing, destroy after test run
- **prod** — only deploy when ready to demo; destroy immediately after

## Teardown All Environments

```bash
for env in dev qa prod; do
  az group delete --name rg-modules-$env --yes --no-wait
done
```

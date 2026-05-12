# Cost Estimate — Custom VNet

## Monthly Cost Breakdown

| Resource | SKU / Tier | Qty | Unit Cost | Monthly Total |
|---|---|---|---|---|
| Virtual Network | Standard | 1 | Free | $0.00 |
| Subnets | — | 3 | Free | $0.00 |
| Network Security Groups | — | 3 | Free | $0.00 |
| Route Tables | — | 2 | Free | $0.00 |
| NAT Gateway | Standard | 1 | ~$32.00 | $32.00 |
| Public IP (Static, Standard) | Standard | 1 | ~$3.65 | $3.65 |
| NAT Gateway data processing | per GB | ~10 GB | $0.045/GB | ~$0.45 |

## Total Estimated Monthly Cost: ~$36/month

---

## Cost Notes

- **VNet, Subnets, NSGs, Route Tables** are all free — no charge for the network constructs themselves
- **NAT Gateway** is the main cost driver: ~$32/month base + $0.045/GB processed
- **Public IP** Standard SKU is ~$3.65/month when associated; $0.005/hour when unassociated
- Data transfer within the same region is free; cross-region costs apply

## Cost Optimization Tips

- Delete the NAT Gateway when not actively learning — it charges even with zero traffic
- Use Basic SKU Public IP if you don't need zone redundancy (cheaper but being deprecated)
- NAT Gateway idle timeout default is 4 minutes — increase to reduce reconnection overhead

## Teardown to $0

```bash
az group delete --name rg-vnet-lab --yes --no-wait
```

All resources in the group are deleted, billing stops within minutes.

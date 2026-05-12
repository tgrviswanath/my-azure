# Cost Estimate — Terraform Basics

## Monthly Cost Breakdown

| Resource | SKU / Tier | Qty | Unit Cost | Monthly Total |
|---|---|---|---|---|
| Resource Group | — | 1 | Free | $0.00 |
| Storage Account | Standard LRS | 1 | ~$0.018/GB | ~$0.02 |
| Storage transactions | per 10K | minimal | $0.0004 | ~$0.00 |

## Total Estimated Monthly Cost: ~$0.02/month

---

## Cost Notes

- Resource Groups are completely free — they're just logical containers
- Storage Account base cost is essentially zero for learning (you're storing almost nothing)
- The main cost would be if you store large amounts of data or make millions of API calls
- This is the cheapest possible Azure lab — perfect for learning Terraform without worrying about cost

## Teardown to $0

```bash
terraform destroy
# or
az group delete --name rg-terraform-basics --yes --no-wait
```

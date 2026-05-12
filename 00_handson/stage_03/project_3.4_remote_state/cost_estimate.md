# Cost Estimate — Terraform Remote State

## Monthly Cost Breakdown

| Resource | SKU / Tier | Usage | Monthly Cost |
|---|---|---|---|
| Storage Account | Standard LRS | 1 account | Free (base) |
| Blob storage | Standard LRS | ~1 MB state files | ~$0.00002 |
| Blob operations | Read/Write | ~1,000 ops/month | ~$0.0004 |
| Blob versioning | per version | ~10 versions | ~$0.00002 |

## Total Estimated Monthly Cost: ~$0.02/month

---

## Cost Notes

- Terraform state files are tiny (typically 10 KB – 1 MB)
- Even with 100 state files and daily applies, cost is under $0.10/month
- The storage account itself has no base charge for Standard LRS
- Main cost would be if you accidentally store large files in the same account

## What You're Really Paying For

The state storage cost is negligible. The real value is:
- **Team collaboration** — everyone shares the same state
- **State locking** — prevents concurrent applies from corrupting state
- **State history** — blob versioning lets you roll back
- **Security** — state is not in git (which would expose secrets)

## Teardown to $0

```bash
az group delete --name rg-tfstate --yes --no-wait
```

# Cost Estimate — Terraform CI/CD

## Monthly Cost Breakdown

| Resource | Pricing | Usage | Monthly Cost |
|---|---|---|---|
| GitHub Actions (free tier) | 2,000 min/month free | ~50 runs × 5 min | Free |
| GitHub Actions (paid) | $0.008/min (Linux) | If over 2,000 min | ~$0 |
| Azure Service Principal | Free | 1 SP | $0.00 |
| Azure Storage (state) | ~$0.02/month | From project 3.4 | $0.02 |
| Azure Resources (deployed) | Varies | Depends on what TF deploys | Varies |

## Total CI/CD Infrastructure Cost: ~$0.02/month

---

## GitHub Actions Free Tier

| Plan | Free Minutes/Month | Storage |
|---|---|---|
| Free (public repos) | Unlimited | 500 MB |
| Free (private repos) | 2,000 min | 500 MB |
| Team | 3,000 min | 2 GB |
| Enterprise | 50,000 min | 50 GB |

## Typical Pipeline Duration

| Step | Duration |
|---|---|
| Checkout + setup | ~30s |
| terraform init | ~45s |
| terraform fmt + validate | ~15s |
| terraform plan | ~60–120s |
| terraform apply | ~300–600s |
| **Total (plan only)** | **~2–3 min** |
| **Total (apply)** | **~8–12 min** |

## Cost for 50 PRs/month (plan only)

50 runs × 3 min = 150 minutes → well within free tier

## Notes

- The CI/CD pipeline itself is nearly free
- The real cost is the Azure resources that Terraform deploys
- Use `terraform destroy` in a cleanup job to avoid idle resource costs

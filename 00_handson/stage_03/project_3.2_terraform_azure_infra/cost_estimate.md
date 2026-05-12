# Cost Estimate — Full Azure Infrastructure

## Monthly Cost Breakdown

| Resource | SKU / Tier | Qty | Unit Cost | Monthly Total |
|---|---|---|---|---|
| Resource Group | — | 1 | Free | $0.00 |
| Virtual Network + Subnets | — | 1 | Free | $0.00 |
| NSGs | — | 3 | Free | $0.00 |
| Linux VM | Standard_B2s | 1 | ~$30.37 | $30.37 |
| VM OS Disk | Standard HDD 30 GB | 1 | ~$1.20 | $1.20 |
| Application Gateway | Standard_v2 (1 CU) | 1 | ~$125.00 | $125.00 |
| Public IP (App GW) | Standard Static | 1 | ~$3.65 | $3.65 |
| Public IP (VM) | Standard Static | 1 | ~$3.65 | $3.65 |
| Azure SQL Server | — | 1 | Free | $0.00 |
| Azure SQL Database | S1 (20 DTU) | 1 | ~$30.00 | $30.00 |

## Total Estimated Monthly Cost: ~$194/month

---

## Cost Optimization for Learning

Since this is a learning lab, destroy after each session:

| Duration | Estimated Cost |
|---|---|
| 2 hours | ~$0.54 |
| 1 day | ~$6.47 |
| 1 week | ~$45.27 |

## Teardown to $0

```bash
terraform destroy -var="sql_admin_password=YourP@ssw0rd123"
```

Note: App Gateway takes ~5 minutes to delete. SQL Server takes ~2 minutes.

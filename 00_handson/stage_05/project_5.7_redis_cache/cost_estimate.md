# Cost Estimate — Project 5.7

## Summary

| Resource | SKU | Unit Cost | Qty | Monthly Est. |
|---|---|---|---|---|
| Azure Cache for Redis | C1 Standard 1 GB | ~$0.076/hr | 730 hrs | ~$55.48 |
| Azure SQL Database | Basic 5 DTU | ~$0.0068/hr | 730 hrs | ~$4.96 |
| Azure App Service | B1 (1 core, 1.75 GB) | ~$0.018/hr | 730 hrs | ~$13.14 |
| Azure Monitor / Log Analytics | Pay-per-use | ~$2.30/GB ingested | ~1 GB | ~$2.30 |
| Bandwidth (egress) | First 5 GB free | $0.087/GB after | ~1 GB | ~$0.00 |
| **Total** | | | | **~$75.88/month** |

## Notes

- **Dev/test alternative**: Use C0 Basic (~$16/month) instead of C1 Standard. C0 has no SLA, no replication, and no persistence — acceptable for learning but not production.
- **Cost reduction tip**: Deploy Redis only during active development hours. Use `az redis delete` at end of day and `terraform apply` next morning. Redis takes ~15 min to provision.
- **Free tier**: Azure Cache for Redis has no free tier. The cheapest option is C0 Basic at ~$0.022/hr.
- **SQL alternative**: Replace Azure SQL with a local SQLite simulation in `cache_patterns.py` to eliminate the SQL cost entirely during learning.
- **Pricing region**: Estimates based on East US region. West Europe is ~5-10% higher.
- **Persistence**: C1 Standard includes RDB persistence. Enabling AOF persistence adds ~20% to storage costs.
- All prices are approximate and subject to change. Check [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for current rates.

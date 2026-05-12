# Cost Estimate — Project 7.1 Azure Monitor

## Summary

| Resource | SKU / Tier | Unit Cost | Est. Usage | Monthly Cost |
|---|---|---|---|---|
| Log Analytics Workspace | Pay-as-you-go (PerGB2018) | $2.30/GB ingested | ~3 GB/month | $6.90 |
| Log Analytics Retention | Default 31 days free | $0.10/GB after 31 days | 0 GB extra | $0.00 |
| Metric Alert Rules | Standard | $0.10/rule/month | 3 rules | $0.30 |
| Action Group notifications | Email | Free | — | $0.00 |
| Action Group notifications | SMS | $0.016/message | ~10 msgs | $0.16 |
| Action Group notifications | Webhook | Free | — | $0.00 |
| Azure Dashboard | — | Free | 1 dashboard | $0.00 |
| VM (for testing) | Standard_B2s | ~$0.0416/hr | 8 hrs | $0.33 |
| VM OS Disk | Standard SSD 30GB | $1.54/month | 1 disk | $1.54 |
| **Total** | | | | **~$9.23** |

## Notes

- **First 5 GB/month of Log Analytics ingestion is free** under the free tier — for this demo you likely stay under that limit.
- Metric alerts have a **free tier of 1,000 metric time series** per month — basic VM CPU/disk alerts are well within this.
- Log Analytics **retention beyond 31 days** costs $0.10/GB/month — keep at 30 days for demos.
- The VM cost assumes you destroy it after testing. Use `az group delete` to avoid ongoing charges.
- **Azure Monitor platform metrics** (CPU, disk, network on VMs) are collected automatically at no charge — you only pay for Log Analytics ingestion when you route them there.
- SMS notifications cost $0.016 per message in the US — keep action group test notifications minimal.
- For production, consider **Commitment Tier pricing** for Log Analytics: 100 GB/day tier saves ~25% vs pay-as-you-go.
- Azure Dashboards are free regardless of the number of tiles or users.

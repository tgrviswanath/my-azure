# Cost Estimate — Project 7.4 Log Analytics Query Lab

## Summary

| Item | Monthly Cost |
|------|-------------|
| Log Analytics Workspace (first 5GB free) | $0 |
| Log Analytics (above 5GB, ~$2.30/GB) | ~$5-10 |
| NSG Flow Logs storage | ~$0.50 |
| Network Watcher | $0 |
| Scheduled query alerts | ~$0.10/rule |
| **Total** | **~$6-11/month** |

## Notes
- First 5GB of Log Analytics ingestion per month is free
- NSG flow logs can generate significant data — use traffic analytics sampling
- Use commitment tiers for predictable workloads (100GB/day = $196/month vs $230 PAYG)

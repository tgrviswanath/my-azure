# Cost Estimate — Project 9.9 Synapse Data Warehouse

## Summary

| Item | Monthly Cost |
|------|-------------|
| Synapse workspace | $0 |
| Dedicated SQL Pool DW100c (running 8h/day) | ~$29 |
| Dedicated SQL Pool DW100c (running 24/7) | ~$87 |
| ADLS Gen2 storage (~10GB) | ~$0.23 |
| Synapse Pipelines (10 runs) | ~$0.01 |
| **Total (8h/day usage)** | **~$30/month** |

## Notes
- **PAUSE the pool when not in use** — it costs $1.20/hour even when idle
- DW100c is the minimum tier — good for learning
- Production workloads: DW500c+ for better performance
- Serverless SQL Pool is free for queries (pay per TB scanned)

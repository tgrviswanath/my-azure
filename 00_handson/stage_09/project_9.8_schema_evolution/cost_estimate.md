# Cost Estimate — Project 9.8 Schema Evolution & Partitioning

## Summary

| Item | Monthly Cost |
|------|-------------|
| Azure Databricks workspace | $0 (workspace itself) |
| All-purpose cluster (2 workers, ~2h) | ~$4 |
| ADLS Gen2 storage (~1GB) | ~$0.02 |
| Delta Lake (open source) | $0 |
| **Total** | **~$4/month** |

## Notes
- Delta Lake is open source — no additional cost
- Run cluster only when needed — terminate after use
- Use job clusters (cheaper) instead of all-purpose for production

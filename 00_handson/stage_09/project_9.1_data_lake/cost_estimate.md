# Cost Estimate — Project 9.1 Azure Data Lake Storage Gen2

## Summary

| Service | Unit | Quantity | Unit Price | Monthly Cost |
|---|---|---|---|---|
| ADLS Gen2 — Hot tier storage | GB/month | 100 GB | $0.023 | $2.30 |
| ADLS Gen2 — Write operations | per 10K ops | 100 | $0.065 | $0.65 |
| ADLS Gen2 — Read operations | per 10K ops | 500 | $0.0065 | $0.33 |
| ADLS Gen2 — Hierarchical namespace | per 10K ops | 200 | $0.0065 | $0.13 |
| Azure Purview — Data Map | vCore-hour | 4 vCores × 10 hrs | $0.40 | $16.00 |
| Azure Purview — Scan | vCore-hour | 2 vCores × 5 hrs | $0.40 | $4.00 |
| Synapse Analytics — Serverless SQL | TB processed | 0.1 TB | $5.00 | $0.50 |
| Azure Data Factory — Orchestration | per 1K runs | 1 | $1.00 | $1.00 |
| **Total** | | | | **$24.91** |

## Notes

- ADLS Gen2 pricing is based on 100 GB of data across all zones (raw + processed + curated + archive). Actual cost scales linearly with data volume.
- Purview costs are incurred only when scanning. Schedule scans during off-peak hours and limit scan frequency to weekly for dev environments.
- Synapse Serverless SQL charges per TB of data scanned. Use column pruning and partition filters in queries to minimize scanned data — this is the single biggest cost lever.
- Purview Standard tier is required for data lineage and classification features. The free tier only supports basic cataloging.
- ADLS Gen2 HNS operations (rename, move directory) are billed separately from blob operations. Avoid recursive renames on large directories.
- For dev/test: use LRS replication ($0.023/GB) instead of GRS ($0.046/GB). Switch to ZRS or GRS before production.
- Archive tier storage costs $0.001/GB/month but retrieval fees apply ($0.02/GB). Use archive only for data older than 90 days.
- Estimated cost assumes 10 hours of Purview scanning per month. In production with continuous scanning, Purview can cost $100–$500/month.
- **Pause or delete Purview account when not in use** — it charges even when idle.
- Total for a 30-day dev/test cycle with minimal data: approximately **$25/month**.

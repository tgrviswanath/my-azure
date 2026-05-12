# Cost Estimate — Project 9.7: Data Quality with Great Expectations on Azure

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| Great Expectations | Open source | $0 | — | $0.00 |
| Azure Function (Consumption) | Per million executions | $0.20/M | 30 executions | $0.00 |
| Azure Function (Consumption) | Per GB-second | $0.000016 | 30 × 512MB × 30s | $0.007 |
| Azure Blob Storage (Data Docs) | Per GB/month | $0.018 | 0.1 GB | $0.002 |
| Azure Blob Storage (Parquet data) | Per GB/month | $0.018 | 5 GB | $0.09 |
| Azure Monitor (alerts) | Per alert rule | $0.10/rule | 2 rules | $0.20 |
| Event Grid (blob trigger) | Per million events | $0.60/M | 30 events | $0.00 |
| **Total** | | | | **~$0.30/month** |

## Notes

- **Great Expectations is free**: The open-source library has no cost. GX Cloud (managed service) starts at $500/month.
- **Azure Function Consumption plan**: First 1 million executions/month are free. For 30 daily validations, cost is essentially $0.
- **Data Docs storage**: HTML reports are tiny (< 1 MB each). 30 days × 1 MB = 30 MB = $0.001/month.
- **The real cost is the data**: Parquet files in ADLS are the main storage cost. 5 GB = $0.09/month.
- **Production estimate**: With 100 validations/day across 10 pipelines, still < $5/month for GX infrastructure.
- **GX Cloud**: If you want a managed UI, collaboration, and alerting, GX Cloud starts at $500/month. Not needed for this lab.

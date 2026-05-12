# Cost Estimate — Project 7.2 Centralized Logging

## Summary

| Resource | SKU / Tier | Unit Cost | Est. Usage | Monthly Cost |
|---|---|---|---|---|
| Log Analytics Workspace | Pay-as-you-go (PerGB2018) | $2.30/GB ingested | ~5 GB/month | $11.50 |
| Log Analytics Retention | Default 31 days free | $0.10/GB after 31 days | 0 GB extra | $0.00 |
| Azure Managed Grafana | Standard | $65.00/month | 1 instance | $65.00 |
| Data Collection Endpoint | — | Free | 1 DCE | $0.00 |
| Data Collection Rule | — | Free | 1 DCR | $0.00 |
| VM (for log generation) | Standard_B2s | ~$0.0416/hr | 8 hrs | $0.33 |
| Storage Account (diagnostics) | Standard LRS | ~$0.018/GB | 1 GB | $0.02 |
| **Total** | | | | **~$76.85** |

## Notes

- **Managed Grafana is the dominant cost** at $65/month — destroy it after the demo to avoid charges.
- **First 5 GB/month of Log Analytics ingestion is free** — for this demo you likely stay under that limit, making the effective Log Analytics cost $0.
- The Logs Ingestion API (DCE + DCR) has **no additional charge** beyond the Log Analytics ingestion cost.
- Diagnostic Settings routing to Log Analytics incurs the standard **$2.30/GB ingestion fee** — be selective about which log categories you enable.
- For production, consider **Commitment Tier pricing**: 100 GB/day tier = ~$196/day vs ~$230/day pay-as-you-go (15% savings).
- Managed Grafana includes **unlimited users and dashboards** — no per-seat cost.
- Alternative to Managed Grafana: self-host Grafana on a B1s VM (~$7.59/month) but requires maintenance.
- Log Analytics **data export** to Storage or Event Hub costs $0.10/GB — useful for long-term archival.

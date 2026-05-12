# Cost Estimate — Project 9.3: Azure Event Hubs + Stream Analytics

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| Event Hubs Namespace (Standard) | Per TU/hour | $0.015/TU-hr | 1 TU × 730 hrs | $10.95 |
| Event Hubs Ingress | Per million events | $0.028/M | 100K events/day = 3M/month | $0.08 |
| Event Hubs Capture (optional) | Per hour | $0.113/hr | 730 hrs | $82.49 |
| Stream Analytics | Per SU/hour | $0.11/SU-hr | 1 SU × 730 hrs | $80.30 |
| ADLS Gen2 Output Storage | Per GB/month | $0.023 | 1 GB | $0.02 |
| Azure Monitor (metrics) | Free | $0 | — | $0.00 |
| **Total (with Capture)** | | | | **~$174/month** |
| **Total (without Capture)** | | | | **~$91/month** |

## Notes

- **Stream Analytics is the biggest cost**: 1 SU = ~$80/month. Stop the job when not processing.
  - `az stream-analytics job stop --resource-group $RG --job-name asa-orders-aggregator`
- **Event Hubs Capture**: Optional feature that auto-saves raw events to ADLS/Blob. Adds ~$82/month but provides replay capability.
- **Scaling**: 1 TU handles 1 MB/s ingress. For high-volume production, use Premium tier (auto-inflate TUs).
- **Lab cost reduction**:
  - Stop Stream Analytics job when not running producer: saves $80/month
  - Use Basic tier Event Hubs for simple testing (no consumer groups, 1-day retention): ~$9/month
  - Delete namespace after lab: `az group delete --name $RG --yes`
- **Production estimate**: 10 TUs + 3 SUs + Capture ≈ $400-600/month
- **Kafka compatibility**: Event Hubs Standard/Premium supports Kafka protocol — existing Kafka producers work without code changes.

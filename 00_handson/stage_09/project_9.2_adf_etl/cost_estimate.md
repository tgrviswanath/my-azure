# Cost Estimate — Project 9.2: Azure Data Factory ETL Pipeline

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| ADF Pipeline Runs | Per 1000 runs | $1.00 | 30 runs/day = 900/month | $0.90 |
| ADF Copy Activity (DIU-hours) | Per DIU-hour | $0.25 | 30 runs × 4 DIU × 0.1hr | $3.00 |
| ADF Data Flow (vCore-hours) | Per vCore-hour | $0.274 | 30 runs × 8 vCores × 0.5hr | $32.88 |
| ADF Orchestration (activity runs) | Per 1000 activities | $1.00 | 90 activities/month | $0.09 |
| ADF Trigger (schedule) | Per 1000 runs | $0.001 | 30 trigger runs | $0.00 |
| ADLS Gen2 Storage | Per GB/month | $0.023 | 10 GB | $0.23 |
| ADLS Gen2 Operations | Per 10K ops | $0.004 | 100K ops | $0.04 |
| Synapse SQL Pool (DW100c) | Per hour | $1.20 | 8 hrs/day × 30 days | $288.00 |
| **Total (with Synapse running 24/7)** | | | | **~$864/month** |
| **Total (Synapse paused, ADF only)** | | | | **~$5-20/month** |

## Notes

- **Biggest cost driver**: Synapse Dedicated SQL Pool at $1.20/hour. **PAUSE it when not in use!**
  - `az synapse sql pool pause --name sqldw --workspace-name <name> --resource-group <rg>`
- **Data Flow is expensive**: Each Data Flow run spins up a Spark cluster. Use Copy Activity for simple transformations.
- **DIU optimization**: ADF auto-selects DIU count. Set `parallelCopies` and `dataIntegrationUnits` explicitly to control cost.
- **Serverless SQL Pool**: Use Synapse Serverless (pay per TB scanned, ~$5/TB) instead of Dedicated Pool for ad-hoc queries.
- **Lab estimate**: With Synapse paused and 1 pipeline run/day, total is ~$5-20/month.
- **Cost monitoring**: Set ADF budget alerts in Azure Cost Management.

## Cost Optimization Commands

```bash
# Pause Synapse SQL Pool when not in use
az synapse sql pool pause \
  --name sqldw \
  --workspace-name $SYNAPSE_NAME \
  --resource-group $RG

# Resume when needed
az synapse sql pool resume \
  --name sqldw \
  --workspace-name $SYNAPSE_NAME \
  --resource-group $RG

# Check ADF pipeline run costs
az datafactory pipeline-run query-by-factory \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --last-updated-after "2024-01-01T00:00:00Z" \
  --last-updated-before "2024-12-31T00:00:00Z" \
  --query "value[].{Pipeline:pipelineName, Status:status, Duration:durationMs}" \
  --output table
```

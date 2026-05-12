# Cost Estimate — Project 9.6: dbt Transformation Pipeline on Azure Synapse

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| dbt Core | Open source | $0 | — | $0.00 |
| dbt Cloud (optional) | Per seat/month | $50/seat | 1 seat | $50.00 |
| Synapse Dedicated SQL Pool (DW100c) | Per hour | $1.20/hr | 8 hrs/day × 30 days | $288.00 |
| Synapse Workspace | Free | $0 | — | $0.00 |
| ADLS Gen2 Storage | Per GB/month | $0.023 | 10 GB | $0.23 |
| **Total (Synapse running 8 hrs/day)** | | | | **~$288/month** |
| **Total (Synapse paused, dbt only)** | | | | **~$0/month** |

## Notes

- **dbt Core is completely free**: The CLI tool, all adapters, and all features are open source.
- **dbt Cloud**: Adds a web UI, job scheduling, and CI/CD. $50/seat/month. Not needed for this lab.
- **Synapse is the cost**: DW100c at $1.20/hour. **PAUSE when not running dbt!**
  - `az synapse sql pool pause --name sqldw --workspace-name <name> --resource-group <rg>`
- **Synapse Serverless**: For dbt development, consider Synapse Serverless SQL Pool (pay per TB scanned, ~$5/TB). Much cheaper for ad-hoc queries.
- **Lab estimate**: With Synapse paused between dbt runs (1 hour/day), cost is ~$36/month.
- **Production**: Synapse DW200c running 24/7 = ~$1,750/month. Use auto-pause and scale down overnight.

## Cost Optimization Commands

```bash
# Pause Synapse SQL Pool
az synapse sql pool pause \
  --name sqldw \
  --workspace-name synapse-dbt-lab \
  --resource-group rg-dbt-lab

# Resume for dbt run
az synapse sql pool resume \
  --name sqldw \
  --workspace-name synapse-dbt-lab \
  --resource-group rg-dbt-lab

# Check pool status
az synapse sql pool show \
  --name sqldw \
  --workspace-name synapse-dbt-lab \
  --resource-group rg-dbt-lab \
  --query status -o tsv
```

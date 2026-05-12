# Cost Estimate — Project 9.4: Spark Processing on Azure Databricks

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| Databricks Standard (All-purpose) | Per DBU/hour | $0.07/DBU | 2 workers × 4 DBU × 4 hrs/day × 30 days | $67.20 |
| Azure VMs (Standard_DS3_v2 × 3) | Per VM/hour | $0.19/hr | 3 VMs × 4 hrs/day × 30 days | $68.40 |
| ADLS Gen2 Storage | Per GB/month | $0.023 | 50 GB | $1.15 |
| ADLS Gen2 Operations | Per 10K ops | $0.004 | 500K ops | $0.20 |
| Key Vault | Per 10K operations | $0.03 | 10K ops | $0.03 |
| **Total (4 hrs/day)** | | | | **~$137/month** |
| **Total (1 hr/day lab use)** | | | | **~$50/month** |

## Notes

- **DBU pricing**: Standard tier = $0.07/DBU. Premium tier (Unity Catalog, enhanced security) = $0.15/DBU.
- **VM cost is separate**: Databricks charges DBUs on top of Azure VM costs. Total = DBU cost + VM cost.
- **Auto-termination is critical**: Set `autotermination_minutes=30`. An idle 2-worker cluster costs ~$2/hour.
- **Job clusters vs All-purpose**: Job clusters (for scheduled jobs) are cheaper than All-purpose (interactive). Use job clusters in production.
- **Spot instances**: Use Azure Spot VMs for workers to save 60-80%. Set `availability: SPOT_WITH_FALLBACK_AZURE`.
- **Delta Lake is free**: Delta Lake is open source and included in Databricks Runtime. No extra charge.
- **Lab cost reduction**:
  - Terminate cluster when not in use
  - Use single-node cluster for development (1 VM, no workers)
  - Use Databricks Community Edition (free, limited) for learning
- **Production estimate**: 10-worker cluster running 8 hrs/day ≈ $500-800/month

## Cost Optimization Commands

```bash
# Terminate cluster when done
databricks clusters delete --cluster-id $CLUSTER_ID

# Check cluster state
databricks clusters get --cluster-id $CLUSTER_ID --output JSON | python -c "
import json, sys; c = json.load(sys.stdin); print(c['state'])
"

# List running clusters
databricks clusters list --output JSON | python -c "
import json, sys
for c in json.load(sys.stdin)['clusters']:
    if c['state'] == 'RUNNING':
        print(f\"{c['cluster_id']}: {c['cluster_name']} - {c['state']}\")
"
```

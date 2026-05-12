# Cost Estimate — Project 8.5: Microsoft Sentinel SIEM

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| Log Analytics Workspace | Per GB ingested | $2.30/GB | 2 GB/day = 60 GB | $138.00 |
| Microsoft Sentinel | Per GB analyzed | $2.46/GB | 2 GB/day = 60 GB | $147.60 |
| Logic Apps (Playbook) | Per action execution | $0.000025/action | 100 runs × 5 actions | $0.01 |
| Azure AD (P2 for CA) | Per user/month | $9.00/user | 5 users (lab) | $45.00 |
| Azure Monitor Alerts | Per alert rule | $0.10/rule/month | 5 rules | $0.50 |
| **Total (full lab)** | | | | **~$331/month** |
| **Total (minimal — free sources only)** | | | | **~$5-20/month** |

## Notes

- **Biggest cost driver**: Log Analytics ingestion + Sentinel per-GB charge. At 2 GB/day this adds up fast.
- **Cost reduction strategies**:
  - Use **Commitment Tiers** (100 GB/day = $196/day vs pay-as-you-go $276/day — 29% savings)
  - Enable only **free data connectors** first: Azure Activity Log, Azure AD Audit Logs (free up to 5 GB/day)
  - Set **data collection rules** to filter noisy tables (SecurityEvent can be very high volume)
  - Use **Basic Logs** tier for verbose tables ($0.50/GB vs $2.30/GB, but limited query)
- **Lab estimate**: With minimal data (Activity Log only, ~0.5 GB/month), cost is ~$5-20/month
- **Free trial**: Microsoft Sentinel has a 31-day free trial for new workspaces (up to 10 GB/day free)
- **Azure AD P2**: Only needed for Conditional Access and PIM features. Skip for basic Sentinel lab.
- Always **delete the resource group** after the lab to stop all charges.

## Cost Optimization Commands

```bash
# Check current ingestion volume
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "Usage | summarize sum(Quantity) by DataType | order by sum_Quantity desc" \
  --output table

# Set workspace daily cap to limit costs
az monitor log-analytics workspace update \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --ingestion-access Enabled \
  --query-access Enabled
# Note: daily cap set in portal under Usage and estimated costs
```

# Cost Estimate — Project 9.5: Apache Airflow on Azure AKS

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| AKS Standard tier | Per cluster/hour | $0.10/hr | 730 hrs | $73.00 |
| AKS Nodes (2x Standard_D2s_v3) | Per VM/hour | $0.096/hr | 2 × 730 hrs | $140.16 |
| Azure PostgreSQL Flexible (B1ms) | Per hour | $0.021/hr | 730 hrs | $15.33 |
| Azure Container Registry (Basic) | Per month | $5.00 | 1 registry | $5.00 |
| Load Balancer (for webserver) | Per hour | $0.025/hr | 730 hrs | $18.25 |
| Managed Disk (OS disks) | Per GB/month | $0.10/GB | 2 × 30 GB | $6.00 |
| Azure Monitor (logs) | Per GB | $2.30/GB | 1 GB | $2.30 |
| **Total** | | | | **~$260/month** |

## Notes

- **AKS is the biggest cost**: 2 nodes × Standard_D2s_v3 = ~$140/month just for VMs.
- **Cost reduction strategies**:
  - Use **Spot node pools** for Airflow workers: 60-80% cheaper
  - Use **B2s nodes** instead of D2s_v3 for dev: ~$35/month for 2 nodes
  - **Stop AKS cluster** when not in use: `az aks stop --name aks-airflow --resource-group $RG`
  - Use **Azure Container Apps** instead of AKS for simpler Airflow deployments
- **Alternative**: Azure Managed Airflow (via Azure Data Factory managed Airflow) — no AKS needed, ~$50/month
- **Production estimate**: 3-node cluster + PostgreSQL + monitoring ≈ $400-600/month
- **Lab cost reduction**: Stop AKS when not testing. Restart takes ~5 minutes.

## Cost Optimization Commands

```bash
# Stop AKS cluster (saves VM costs, keeps cluster config)
az aks stop --name aks-airflow --resource-group $RG

# Start AKS cluster
az aks start --name aks-airflow --resource-group $RG

# Scale down to 1 node when idle
az aks scale --name aks-airflow --resource-group $RG --node-count 1

# Check current node count
az aks show --name aks-airflow --resource-group $RG \
  --query agentPoolProfiles[0].count -o tsv
```

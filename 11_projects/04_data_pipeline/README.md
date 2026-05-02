# Project 04 — Data Pipeline (Azure Storage + Processing)

## Architecture
```
Data Sources → Azure Event Hubs (ingestion)
                      ↓
              Azure Stream Analytics (real-time processing)
                      ↓
              Azure Data Lake Storage Gen2 (raw data)
                      ↓
              Azure Databricks / Synapse Analytics (batch processing)
                      ↓
              Azure Synapse SQL Pool (data warehouse)
                      ↓
              Power BI / Azure Analysis Services (reporting)

Orchestration: Azure Data Factory (pipeline scheduling)
Monitoring:    Azure Monitor + Log Analytics
```

## Pipeline Stages
1. **Ingest**: Event Hubs receives streaming data (IoT, clickstream, logs)
2. **Stream**: Stream Analytics processes real-time aggregations
3. **Store**: ADLS Gen2 stores raw + processed data (Bronze/Silver/Gold)
4. **Transform**: Databricks/Synapse transforms data (ETL)
5. **Serve**: Synapse SQL Pool for analytics queries
6. **Visualize**: Power BI dashboards

## Medallion Architecture
```
Bronze (Raw):   Exact copy of source data, immutable
Silver (Clean): Validated, deduplicated, standardized
Gold (Curated): Business-ready aggregations, KPIs
```

## Deploy
```bash
# Create infrastructure
az deployment group create \
  --resource-group rg-datapipeline-prod \
  --template-file infrastructure/main.bicep

# Create Event Hub
az eventhubs namespace create \
  --name evhns-pipeline-prod \
  --resource-group rg-datapipeline-prod \
  --sku Standard \
  --capacity 2

az eventhubs eventhub create \
  --name events \
  --namespace-name evhns-pipeline-prod \
  --resource-group rg-datapipeline-prod \
  --partition-count 4 \
  --message-retention 7

# Create ADLS Gen2
az storage account create \
  --name adlspipelineprod \
  --resource-group rg-datapipeline-prod \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --enable-hierarchical-namespace true

# Create containers (Bronze/Silver/Gold)
for tier in bronze silver gold; do
  az storage fs create \
    --name $tier \
    --account-name adlspipelineprod
done
```

## Cost Estimate
| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Event Hubs (Standard) | 2 TU | ~$45 |
| ADLS Gen2 | 1TB ZRS | ~$25 |
| Stream Analytics | 3 SU | ~$240 |
| Synapse Analytics | 100 DWU | ~$730 |
| Data Factory | 1000 runs | ~$50 |
| **Total** | | **~$1,090/mo** |

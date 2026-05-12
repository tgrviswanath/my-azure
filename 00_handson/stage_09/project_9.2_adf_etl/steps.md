# Steps — Project 9.2: Azure Data Factory ETL Pipeline

## Phase 1: Create ADF + Linked Services

```bash
# Variables
RG="rg-adf-etl-lab"
LOCATION="eastus"
ADF_NAME="adf-etl-lab-$(date +%s)"
STORAGE_NAME="stadfetl$(date +%s | tail -c 6)"
SYNAPSE_NAME="synapse-etl-lab"
SQL_POOL="sqldw"

# Create resource group
az group create --name $RG --location $LOCATION --tags project=adf-etl stage=09

# Create Storage Account (ADLS Gen2)
az storage account create \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hierarchical-namespace true \
  --access-tier Hot

# Create containers
az storage container create --name raw       --account-name $STORAGE_NAME
az storage container create --name processed --account-name $STORAGE_NAME
az storage container create --name rejected  --account-name $STORAGE_NAME

# Upload sample data
cat > /tmp/orders_sample.csv << 'EOF'
order_id,customer_id,product,amount,order_date,status
1001,C001,Widget A,29.99,2024-01-15,completed
1002,C002,Widget B,49.99,2024-01-15,completed
1003,C003,Widget A,29.99,2024-01-16,pending
1004,C001,Widget C,99.99,2024-01-16,completed
1005,C004,Widget B,49.99,2024-01-17,cancelled
EOF

az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name raw \
  --name orders/2024/01/orders_sample.csv \
  --file /tmp/orders_sample.csv

# Create Azure Data Factory
az datafactory create \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --location $LOCATION

# Create Linked Service for ADLS Gen2
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --query "[0].value" -o tsv)

az datafactory linked-service create \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --linked-service-name "ls_adls_source" \
  --properties '{
    "type": "AzureBlobStorage",
    "typeProperties": {
      "connectionString": "DefaultEndpointsProtocol=https;AccountName='"$STORAGE_NAME"';AccountKey='"$STORAGE_KEY"';EndpointSuffix=core.windows.net"
    }
  }'

echo "ADF and linked services created."
echo "ADF Name: $ADF_NAME"
echo "Storage: $STORAGE_NAME"
```

## Phase 2: Create Datasets (ADLS Source, Synapse Sink)

```bash
# Create source dataset (CSV in ADLS)
az datafactory dataset create \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --dataset-name "ds_orders_csv_source" \
  --properties '{
    "type": "DelimitedText",
    "linkedServiceName": {
      "referenceName": "ls_adls_source",
      "type": "LinkedServiceReference"
    },
    "typeProperties": {
      "location": {
        "type": "AzureBlobStorageLocation",
        "container": "raw",
        "folderPath": "orders/2024/01",
        "fileName": "orders_sample.csv"
      },
      "columnDelimiter": ",",
      "firstRowAsHeader": true,
      "encodingName": "UTF-8"
    },
    "schema": [
      {"name": "order_id", "type": "String"},
      {"name": "customer_id", "type": "String"},
      {"name": "product", "type": "String"},
      {"name": "amount", "type": "String"},
      {"name": "order_date", "type": "String"},
      {"name": "status", "type": "String"}
    ]
  }'

# Create sink dataset (Parquet in processed container)
az datafactory dataset create \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --dataset-name "ds_orders_parquet_sink" \
  --properties '{
    "type": "Parquet",
    "linkedServiceName": {
      "referenceName": "ls_adls_source",
      "type": "LinkedServiceReference"
    },
    "typeProperties": {
      "location": {
        "type": "AzureBlobStorageLocation",
        "container": "processed",
        "folderPath": "orders"
      },
      "compressionCodec": "snappy"
    }
  }'

echo "Datasets created."
```

## Phase 3: Create Copy Pipeline

```bash
# Create pipeline with Copy Activity
az datafactory pipeline create \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --pipeline-name "pl_copy_orders" \
  --pipeline '{
    "activities": [
      {
        "name": "CopyOrdersToParquet",
        "type": "Copy",
        "inputs": [{"referenceName": "ds_orders_csv_source", "type": "DatasetReference"}],
        "outputs": [{"referenceName": "ds_orders_parquet_sink", "type": "DatasetReference"}],
        "typeProperties": {
          "source": {
            "type": "DelimitedTextSource",
            "storeSettings": {"type": "AzureBlobStorageReadSettings", "recursive": false}
          },
          "sink": {
            "type": "ParquetSink",
            "storeSettings": {"type": "AzureBlobStorageWriteSettings"}
          },
          "enableStaging": false,
          "translator": {
            "type": "TabularTranslator",
            "typeConversion": true,
            "typeConversionSettings": {"allowDataTruncation": true}
          }
        }
      }
    ]
  }'

echo "Copy pipeline created."
```

## Phase 4: Add Data Flow for Transformation

```bash
# Data Flow is created in ADF Studio (portal) or via ARM template
# The transformation logic:
# 1. Filter: status == 'completed'
# 2. DerivedColumn: amount_usd = toDecimal(amount), year = year(toDate(order_date))
# 3. Aggregate: group by product, year → sum(amount_usd) as total_revenue, count() as order_count
# 4. Sink: write to processed/aggregated/

# Create pipeline with Data Flow activity
az datafactory pipeline create \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --pipeline-name "pl_transform_orders" \
  --pipeline '{
    "activities": [
      {
        "name": "TransformOrders",
        "type": "ExecuteDataFlow",
        "typeProperties": {
          "dataflow": {
            "referenceName": "df_transform_orders",
            "type": "DataFlowReference"
          },
          "compute": {
            "coreCount": 8,
            "computeType": "General"
          },
          "traceLevel": "Fine"
        }
      }
    ]
  }'

echo "Data Flow pipeline created."
echo "Note: Create the actual Data Flow 'df_transform_orders' in ADF Studio."
```

## Phase 5: Trigger and Monitor

```bash
# Create a schedule trigger (daily at 2am UTC)
az datafactory trigger create \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --trigger-name "tr_daily_etl" \
  --properties '{
    "type": "ScheduleTrigger",
    "typeProperties": {
      "recurrence": {
        "frequency": "Day",
        "interval": 1,
        "startTime": "2024-01-01T02:00:00Z",
        "timeZone": "UTC"
      }
    },
    "pipelines": [
      {
        "pipelineReference": {"referenceName": "pl_copy_orders", "type": "PipelineReference"},
        "parameters": {}
      }
    ]
  }'

# Start the trigger
az datafactory trigger start \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --trigger-name "tr_daily_etl"

# Manually trigger a pipeline run
RUN_ID=$(az datafactory pipeline create-run \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --pipeline-name "pl_copy_orders" \
  --query runId -o tsv)

echo "Pipeline run started: $RUN_ID"

# Monitor the run
az datafactory pipeline-run show \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --run-id $RUN_ID

# Wait and check status
sleep 30
az datafactory pipeline-run show \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --run-id $RUN_ID \
  --query "{Status:status, Duration:durationMs, Message:message}" \
  --output table

# List activity runs for the pipeline run
az datafactory activity-run query-by-pipeline-run \
  --resource-group $RG \
  --factory-name $ADF_NAME \
  --run-id $RUN_ID \
  --last-updated-after "2024-01-01T00:00:00Z" \
  --last-updated-before "2025-12-31T00:00:00Z" \
  --output table

# Run the Python trigger script for full monitoring
cd code
python adf_trigger.py

# Cleanup
az group delete --name $RG --yes --no-wait
```

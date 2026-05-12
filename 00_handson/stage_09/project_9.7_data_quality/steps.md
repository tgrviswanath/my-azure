# Steps — Project 9.7: Data Quality with Great Expectations on Azure

## Phase 1: Install Great Expectations

```bash
# Create virtual environment
python -m venv gx-env
source gx-env/bin/activate

# Install Great Expectations and Azure dependencies
pip install great-expectations[azure]
pip install azure-storage-blob azure-identity pyarrow pandas

# Verify installation
great_expectations --version
# great_expectations, version 0.18.x

# Initialize GX project
mkdir gx-project && cd gx-project
great_expectations init

# Expected output:
# ================================================================================
# Great Expectations is now set up.
# ================================================================================
# - The following Data Context has been created:
#   great_expectations/
#   ├── great_expectations.yml
#   ├── expectations/
#   ├── checkpoints/
#   └── uncommitted/
```

## Phase 2: Create Expectation Suite

```bash
# Create expectation suite via CLI
great_expectations suite new

# Or programmatically (see validate_orders.py)
python << 'EOF'
import great_expectations as gx

context = gx.get_context()

# Create suite
suite = context.add_expectation_suite(expectation_suite_name="orders_suite")

print(f"Suite created: {suite.expectation_suite_name}")
print(f"Expectations: {len(suite.expectations)}")
EOF

# List suites
great_expectations suite list
```

## Phase 3: Run Validation Against Parquet

```bash
# Set environment variables
export AZURE_STORAGE_ACCOUNT="your-storage-account"
export AZURE_STORAGE_CONTAINER="processed"
export AZURE_BLOB_PATH="orders/2024/01/orders.parquet"

# Download sample Parquet for local testing
az storage blob download \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --container-name $AZURE_STORAGE_CONTAINER \
  --name $AZURE_BLOB_PATH \
  --file /tmp/orders.parquet

# Run validation
python code/validate_orders.py

# View Data Docs
great_expectations docs build
great_expectations docs serve
# Open http://localhost:8080 to see HTML validation report
```

## Phase 4: Integrate with ADF Pipeline

```bash
# Create Azure Function to trigger validation
# Function is triggered by Event Grid when new blob arrives in ADLS

# Deploy Function App via Terraform
cd terraform
terraform init
terraform apply -auto-approve

FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

# Deploy function code
cd ../code
func init azure_function --python
cd azure_function

# Create function
func new --name ValidateOrders --template "Azure Blob Storage trigger"

# Deploy to Azure
func azure functionapp publish $FUNCTION_APP_NAME

# Test the function
curl -X POST \
  "https://$FUNCTION_APP_NAME.azurewebsites.net/api/ValidateOrders" \
  -H "Content-Type: application/json" \
  -d '{
    "storage_account": "'"$AZURE_STORAGE_ACCOUNT"'",
    "container": "processed",
    "blob_path": "orders/2024/01/orders.parquet"
  }'

# Set up Event Grid subscription to trigger on blob creation
az eventgrid event-subscription create \
  --name "validate-on-blob-create" \
  --source-resource-id $(az storage account show --name $AZURE_STORAGE_ACCOUNT --resource-group $RG --query id -o tsv) \
  --endpoint "https://$FUNCTION_APP_NAME.azurewebsites.net/api/ValidateOrders" \
  --endpoint-type webhook \
  --included-event-types Microsoft.Storage.BlobCreated \
  --subject-begins-with "/blobServices/default/containers/processed/blobs/orders/"
```

## Phase 5: View Data Docs

```bash
# Data Docs are stored in Azure Blob Storage
# View locally
great_expectations docs build
great_expectations docs serve

# Or access from Azure Blob Storage
DOCS_URL=$(az storage blob url \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --container-name data-docs \
  --name index.html \
  --output tsv)

echo "Data Docs URL: $DOCS_URL"

# Set up static website hosting on storage account
az storage blob service-properties update \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --static-website \
  --index-document index.html

# Upload Data Docs to static website
az storage blob upload-batch \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --destination '$web' \
  --source great_expectations/uncommitted/data_docs/local_site/

STATIC_URL=$(az storage account show \
  --name $AZURE_STORAGE_ACCOUNT \
  --resource-group $RG \
  --query primaryEndpoints.web -o tsv)

echo "Data Docs static site: $STATIC_URL"

# Cleanup
az group delete --name rg-data-quality-lab --yes --no-wait
```

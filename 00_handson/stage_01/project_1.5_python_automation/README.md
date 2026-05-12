# Project 1.5 — Python Azure Automation

## What This Does
Automates Azure resource management using the Azure Python SDK. Covers blob storage uploads with progress tracking, VM start/stop automation, and folder sync/backup scripts.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Blob Storage | File upload target |
| Azure Virtual Machines | Start/stop automation |
| Azure SDK (azure-identity) | DefaultAzureCredential authentication |
| Azure SDK (azure-storage-blob) | Blob operations |
| Azure SDK (azure-mgmt-compute) | VM management |

## How to Deploy
```bash
# Deploy storage account
cd terraform
terraform init
terraform apply -auto-approve

# Install dependencies
pip install azure-identity azure-storage-blob azure-mgmt-compute azure-mgmt-resource

# Authenticate
az login

# Run blob uploader
python scripts/blob_uploader.py --folder ./sample_data --container uploads
```

## Folder Structure
```
project_1.5_python_automation/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
├── terraform/
│   └── main.tf
└── scripts/
    └── blob_uploader.py
```

## Authentication Pattern
```python
from azure.identity import DefaultAzureCredential

# DefaultAzureCredential tries these in order:
# 1. Environment variables (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID)
# 2. Workload Identity (Kubernetes)
# 3. Managed Identity (Azure VM/Function/Container)
# 4. Azure CLI (az login)
# 5. Azure PowerShell
# 6. Interactive browser

credential = DefaultAzureCredential()
```

## Lessons Learned
- `DefaultAzureCredential` works everywhere — local dev (az login) and production (managed identity)
- Never hardcode credentials — always use `DefaultAzureCredential` or environment variables
- `BlobServiceClient` is the top-level client; `ContainerClient` and `BlobClient` are scoped
- Use `upload_blob(overwrite=True)` for idempotent uploads
- `azure-mgmt-compute` for VM operations; `azure-mgmt-resource` for resource groups
- Batch operations (upload_batch) are faster than individual uploads for many files
- Always handle `ResourceNotFoundError` and `HttpResponseError` from Azure SDK

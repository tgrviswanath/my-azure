# Project 6.3 — Azure DevOps + Terraform Pipeline

## What This Does
Builds a CI/CD pipeline in Azure DevOps that runs Terraform — plan on every PR, apply on merge to main. Uses Azure Storage as the Terraform backend.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure DevOps Pipelines | CI/CD orchestration |
| Azure Storage | Terraform remote state backend |
| Service Connection | Authenticate ADO to Azure |
| Terraform | Infrastructure as code |

## Architecture
```
Developer pushes code
    │
    ▼
Azure DevOps Pipeline
    ├── PR → Stage: Validate + Plan (comment on PR)
    └── Merge to main → Stage: Apply (with approval gate)
                │
                ▼
        Azure Resources created/updated
```

## How to Run
```bash
# 1. Create storage account for state
az storage account create --name tfstateado001 --resource-group rg-terraform-state --sku Standard_LRS
az storage container create --name tfstate --account-name tfstateado001

# 2. Create service connection in ADO (Project Settings → Service Connections)
# 3. Import azure-pipelines.yml into ADO pipeline
```

## Lessons Learned
- Use `azurerm` backend with Azure Storage — built-in locking via blob leases
- Service connections use managed identity or service principal — prefer managed identity
- Add approval gates before `terraform apply` in production
- Store `terraform plan` output as pipeline artifact for audit trail

## Code

### `code/azure-pipelines.yml` — Full ADO pipeline

```bash
# Import into Azure DevOps:
# Pipelines → New Pipeline → Azure Repos Git → select repo → Existing YAML file
```

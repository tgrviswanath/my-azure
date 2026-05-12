# Architecture — Terraform Remote State

## ASCII Diagram

```
  Developer A                    Developer B
  ───────────                    ───────────
  terraform apply                terraform apply
       │                               │
       │ 1. Acquire lease              │ 1. Try to acquire lease
       ▼                               ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  Azure Storage Account (stterraformstateXXXXXX)             │
  │                                                               │
  │  Container: tfstate                                           │
  │  ┌─────────────────────────────────────────────────────┐    │
  │  │  Blob: project/terraform.tfstate                     │    │
  │  │                                                       │    │
  │  │  Content: { "version": 4, "resources": [...] }       │    │
  │  │                                                       │    │
  │  │  Lease status: LOCKED (by Developer A)               │    │
  │  │  ← Developer B gets: "Error acquiring state lock"    │    │
  │  │                                                       │    │
  │  │  Versions (blob versioning enabled):                  │    │
  │  │    v3 — 2024-01-03 (current)                         │    │
  │  │    v2 — 2024-01-02                                    │    │
  │  │    v1 — 2024-01-01                                    │    │
  │  └─────────────────────────────────────────────────────┘    │
  └─────────────────────────────────────────────────────────────┘
       │
       │ 2. Read current state
       │ 3. Plan changes
       │ 4. Apply changes
       │ 5. Write new state
       │ 6. Release lease
       ▼
  Azure Resources Created/Updated
```

## Backend Configuration

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stterraformstateXXXXXX"
    container_name       = "tfstate"
    key                  = "project/terraform.tfstate"
    # Authentication: uses ARM_* env vars or az login
  }
}
```

## State File Organization

```
tfstate container/
├── project-2.1/terraform.tfstate    ← VNet project state
├── project-2.2/terraform.tfstate    ← Multi-tier app state
├── project-3.1/terraform.tfstate    ← Terraform basics state
├── dev/terraform.tfstate            ← Dev environment state
├── qa/terraform.tfstate             ← QA environment state
└── prod/terraform.tfstate           ← Prod environment state
```

## Key Concepts

| Concept | Explanation |
|---|---|
| Remote backend | Stores state in Azure Blob instead of local `terraform.tfstate` |
| State locking | Azure Blob lease prevents two people from applying simultaneously |
| Blob versioning | Every state write creates a new version; old versions kept for rollback |
| `terraform init -migrate-state` | Moves existing local state to the remote backend |
| `terraform state pull` | Downloads current remote state to stdout |
| `terraform state push` | Uploads a state file to the remote backend (use with caution) |
| Partial backend config | Use `-backend-config` flag to pass sensitive values without hardcoding |

## Security Best Practices

```bash
# Restrict access to state storage with RBAC
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee <service-principal-id> \
  --scope /subscriptions/<sub>/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/<name>

# Never make the container public
az storage container set-permission \
  --name tfstate \
  --account-name <name> \
  --public-access off
```

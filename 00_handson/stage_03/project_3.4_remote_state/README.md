# Project 3.4 — Terraform Remote State on Azure Storage

## What It Does

Configures Terraform to store state remotely in Azure Blob Storage instead of locally:
- **Azure Storage Account** — stores the `terraform.tfstate` file as a blob
- **Blob container** — `tfstate` container holds state files
- **State locking** — Azure Blob lease mechanism prevents concurrent applies
- **State versioning** — blob versioning keeps history of state changes
- **State migration** — move existing local state to remote backend

This is essential for team collaboration — everyone shares the same state.

## Azure Services Used

| Service | Purpose |
|---|---|
| Azure Storage Account | Hosts the Terraform state backend |
| Blob Container | Stores .tfstate files |
| Blob Lease | State locking (prevents concurrent applies) |
| Blob Versioning | State history and rollback |

## How to Deploy

### Step 1: Bootstrap the state storage (one-time setup)
```bash
pip install azure-storage-blob azure-identity
python code/state_manager.py bootstrap \
  --resource-group rg-tfstate \
  --storage-account stterraformstate$(date +%s | tail -c 6) \
  --container tfstate
```

### Step 2: Configure backend in main.tf
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stterraformstateXXXXXX"
    container_name       = "tfstate"
    key                  = "myproject/terraform.tfstate"
  }
}
```

### Step 3: Initialize with remote backend
```bash
terraform init
# If migrating from local state:
terraform init -migrate-state
```

### Manage state
```bash
python code/state_manager.py list --storage-account stterraformstateXXXXXX
python code/state_manager.py break-lock --storage-account stterraformstateXXXXXX --blob tfstate/myproject/terraform.tfstate
```

## Lessons Learned

- **Never commit `terraform.tfstate` to git** — it contains secrets and causes merge conflicts
- **State locking** — if `terraform apply` crashes, the lease may remain; use `break-lock` to release it
- **State file contains secrets** — storage account should have restricted access (RBAC, not public)
- **One state file per environment** — use different `key` values: `dev/terraform.tfstate`, `prod/terraform.tfstate`
- **State versioning** — enable blob versioning so you can roll back to a previous state if something goes wrong
- **`terraform state mv`** — use to rename resources in state without destroying/recreating them

## Code

See `code/state_manager.py` — bootstraps Azure Storage for Terraform state, lists state files, and breaks stuck lease locks.

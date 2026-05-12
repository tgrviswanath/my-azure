# Deployment Steps — Terraform Remote State

## Phase 1: Create Storage Account for State

```bash
# 1.1 Create resource group for state storage
az group create \
  --name rg-tfstate \
  --location eastus \
  --tags purpose=terraform-state managed_by=manual

# 1.2 Create storage account (globally unique name required)
STORAGE_NAME="stterraformstate$(date +%s | tail -c 6)"
echo "Storage account name: $STORAGE_NAME"

az storage account create \
  --resource-group rg-tfstate \
  --name $STORAGE_NAME \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true

# 1.3 Enable blob versioning (for state history)
az storage account blob-service-properties update \
  --resource-group rg-tfstate \
  --account-name $STORAGE_NAME \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30

# 1.4 Create container for state files
az storage container create \
  --name tfstate \
  --account-name $STORAGE_NAME \
  --auth-mode login

# 1.5 Verify
az storage container list \
  --account-name $STORAGE_NAME \
  --auth-mode login \
  --output table

# 1.6 Or use the Python bootstrap script
python code/state_manager.py bootstrap \
  --resource-group rg-tfstate \
  --storage-account $STORAGE_NAME \
  --container tfstate
```

---

## Phase 2: Configure Backend in Terraform

```bash
# 2.1 Add backend block to main.tf
# Edit terraform/main.tf and add:
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-tfstate"
#     storage_account_name = "stterraformstateXXXXXX"
#     container_name       = "tfstate"
#     key                  = "project-3.4/terraform.tfstate"
#   }
# }

# 2.2 Initialize with the new backend
cd terraform/
terraform init

# Expected output:
# Initializing the backend...
# Successfully configured the backend "azurerm"!
# Terraform will automatically use this backend unless the backend configuration changes.

# 2.3 Verify state is stored in Azure
az storage blob list \
  --container-name tfstate \
  --account-name $STORAGE_NAME \
  --auth-mode login \
  --output table
```

---

## Phase 3: Migrate Existing Local State

```bash
# 3.1 If you have existing local state, migrate it
# First, add the backend block to main.tf (as in Phase 2)

# 3.2 Run init with migrate flag
terraform init -migrate-state

# Expected:
# Do you want to copy existing state to the new backend?
# Type 'yes' to confirm.

# 3.3 Verify local state is now empty / remote state exists
cat terraform.tfstate  # Should be empty or show "no state"

az storage blob list \
  --container-name tfstate \
  --account-name $STORAGE_NAME \
  --auth-mode login \
  --output table
# Should show: project-3.4/terraform.tfstate
```

---

## Phase 4: Test State Locking

```bash
# 4.1 Start a terraform apply in one terminal
terraform apply -auto-approve &

# 4.2 In another terminal, try to apply simultaneously
terraform apply -auto-approve
# Expected error:
# Error: Error acquiring the state lock
# Lock Info:
#   ID:        <lock-id>
#   Path:      tfstate/project-3.4/terraform.tfstate
#   Operation: OperationTypeApply
#   Who:       user@machine
#   Created:   2024-01-01 12:00:00

# 4.3 Check the blob lease in Azure
az storage blob show \
  --container-name tfstate \
  --name "project-3.4/terraform.tfstate" \
  --account-name $STORAGE_NAME \
  --auth-mode login \
  --query "properties.lease"

# 4.4 If lock is stuck, break it
python code/state_manager.py break-lock \
  --storage-account $STORAGE_NAME \
  --blob "project-3.4/terraform.tfstate"
```

---

## Phase 5: List State Files

```bash
# 5.1 List all state files
python code/state_manager.py list \
  --storage-account $STORAGE_NAME

# 5.2 List via Azure CLI
az storage blob list \
  --container-name tfstate \
  --account-name $STORAGE_NAME \
  --auth-mode login \
  --output table

# 5.3 Download state file for inspection (read-only)
az storage blob download \
  --container-name tfstate \
  --name "project-3.4/terraform.tfstate" \
  --account-name $STORAGE_NAME \
  --auth-mode login \
  --file /tmp/state-backup.json

cat /tmp/state-backup.json | python -m json.tool | head -50

# 5.4 Cleanup
az group delete --name rg-tfstate --yes --no-wait
```

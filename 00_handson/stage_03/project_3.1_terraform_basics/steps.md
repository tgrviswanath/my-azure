# Deployment Steps — Terraform Basics

## Phase 1: Install Terraform

```bash
# Windows (winget)
winget install HashiCorp.Terraform

# Windows (Chocolatey)
choco install terraform

# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Linux (Ubuntu/Debian)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Verify
terraform version
# Expected: Terraform v1.x.x
```

---

## Phase 2: Configure azurerm Provider

```bash
# 2.1 Login to Azure
az login
az account show  # Verify correct subscription

# 2.2 Navigate to terraform directory
cd terraform/

# 2.3 Review main.tf — note the provider block:
# terraform {
#   required_providers {
#     azurerm = { source = "hashicorp/azurerm", version = "~> 3.90" }
#   }
# }
# provider "azurerm" { features {} }

# 2.4 Initialize — downloads the azurerm provider plugin
terraform init

# Expected output:
# Initializing provider plugins...
# - Finding hashicorp/azurerm versions matching "~> 3.90"...
# - Installing hashicorp/azurerm v3.x.x...
# Terraform has been successfully initialized!

# 2.5 Check what was downloaded
ls .terraform/providers/
```

---

## Phase 3: Create Resource Group

```bash
# 3.1 Format and validate
terraform fmt
terraform validate
# Expected: Success! The configuration is valid.

# 3.2 Plan — preview what will be created
terraform plan

# Expected output shows:
# + azurerm_resource_group.main will be created
#   + id       = (known after apply)
#   + location = "eastus"
#   + name     = "rg-terraform-basics"

# 3.3 Apply — create the resource group
terraform apply
# Type 'yes' when prompted

# 3.4 Verify in Azure
az group show --name rg-terraform-basics --output table

# 3.5 Look at the state file
cat terraform.tfstate
# This JSON file tracks everything Terraform created
```

---

## Phase 4: Add Storage Account

```bash
# 4.1 The storage account is already in main.tf
# Review the azurerm_storage_account resource block

# 4.2 Plan again — see what will be added
terraform plan
# Expected: 1 to add (storage account), 0 to change, 0 to destroy

# 4.3 Apply
terraform apply

# 4.4 Verify
az storage account list --resource-group rg-terraform-basics --output table

# 4.5 Show state
terraform show
# Displays all resources in current state

# 4.6 List resources in state
terraform state list
# azurerm_resource_group.main
# azurerm_storage_account.main
```

---

## Phase 5: Use Variables and Outputs

```bash
# 5.1 Override default variable values
terraform plan -var="location=westus2" -var="resource_group_name=rg-tf-west"

# 5.2 Use a .tfvars file
cat > terraform.tfvars << EOF
location            = "westus2"
resource_group_name = "rg-tf-west"
storage_account_tier = "Standard"
EOF

terraform plan -var-file="terraform.tfvars"

# 5.3 Show outputs after apply
terraform output
# resource_group_id = "/subscriptions/.../resourceGroups/rg-terraform-basics"
# storage_account_name = "stterraformbasicsXXXXXX"
# storage_account_primary_endpoint = "https://stterraformbasicsXXXXXX.blob.core.windows.net/"

# 5.4 Get a specific output
terraform output storage_account_name

# 5.5 Output as JSON (useful for scripts)
terraform output -json

# 5.6 Destroy everything
terraform destroy
# Type 'yes' when prompted
# Verify: az group list --output table (rg-terraform-basics should be gone)
```

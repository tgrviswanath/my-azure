terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" { default = "rg-databricks-lab" }
variable "location"            { default = "East US" }

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "dbw" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "spark-databricks", stage = "09", env = "lab" }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ── ADLS Gen2 Storage ─────────────────────────────────────────────────────────

resource "azurerm_storage_account" "adls" {
  name                     = "stadbw${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.dbw.name
  location                 = azurerm_resource_group.dbw.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true  # ADLS Gen2

  tags = azurerm_resource_group.dbw.tags
}

resource "azurerm_storage_container" "raw" {
  name                  = "raw"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "delta" {
  name                  = "delta"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

# ── Databricks Workspace ──────────────────────────────────────────────────────

resource "azurerm_databricks_workspace" "dbw" {
  name                = "dbw-spark-lab-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dbw.name
  location            = azurerm_resource_group.dbw.location
  sku                 = "standard"

  tags = azurerm_resource_group.dbw.tags
}

# ── Role Assignment: Databricks workspace managed identity → ADLS ─────────────

resource "azurerm_role_assignment" "dbw_storage" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_workspace.dbw.storage_account_identity[0].principal_id

  depends_on = [azurerm_databricks_workspace.dbw]
}

# ── Key Vault for Service Principal Credentials ───────────────────────────────

resource "azurerm_key_vault" "dbw" {
  name                       = "kv-dbw-${random_string.suffix.result}"
  location                   = azurerm_resource_group.dbw.location
  resource_group_name        = azurerm_resource_group.dbw.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
  }

  tags = azurerm_resource_group.dbw.tags
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "databricks_workspace_url" {
  description = "Databricks workspace URL"
  value       = "https://${azurerm_databricks_workspace.dbw.workspace_url}"
}

output "databricks_workspace_id" {
  value = azurerm_databricks_workspace.dbw.workspace_id
}

output "storage_account_name" {
  value = azurerm_storage_account.adls.name
}

output "storage_account_id" {
  value = azurerm_storage_account.adls.id
}

output "key_vault_name" {
  value = azurerm_key_vault.dbw.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.dbw.vault_uri
}

output "resource_group_name" {
  value = azurerm_resource_group.dbw.name
}

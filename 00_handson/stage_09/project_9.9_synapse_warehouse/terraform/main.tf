# Project 9.9 — Synapse Data Warehouse

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location"       { default = "East US" }
variable "project"        { default = "handson" }
variable "sql_admin_user" { default = "sqladmin" }
variable "sql_admin_pass" {
  default   = "YourPass123!"
  sensitive = true
}

resource "azurerm_resource_group" "synapse" {
  name     = "rg-synapse"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-09" }
}

resource "azurerm_storage_account" "datalake" {
  name                     = "stadl${var.project}syn001"
  resource_group_name      = azurerm_resource_group.synapse.name
  location                 = azurerm_resource_group.synapse.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
}

resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapse"
  storage_account_id = azurerm_storage_account.datalake.id
}

resource "azurerm_synapse_workspace" "main" {
  name                                 = "synapse-${var.project}-001"
  resource_group_name                  = azurerm_resource_group.synapse.name
  location                             = azurerm_resource_group.synapse.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id
  sql_administrator_login              = var.sql_admin_user
  sql_administrator_login_password     = var.sql_admin_pass
  identity { type = "SystemAssigned" }
  tags = { Project = var.project }
}

resource "azurerm_synapse_sql_pool" "main" {
  name                 = "sqldw"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  sku_name             = "DW100c"
  create_mode          = "Default"
  # Auto-pause after 60 minutes of inactivity
  auto_pause {
    delay_in_minutes = 60
  }
  tags = { Project = var.project }
}

# Allow Synapse to access ADLS
resource "azurerm_role_assignment" "synapse_storage" {
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}

output "synapse_sql_endpoint" {
  value = "${azurerm_synapse_workspace.main.name}.sql.azuresynapse.net"
}
output "sql_pool_name"    { value = azurerm_synapse_sql_pool.main.name }
output "storage_account"  { value = azurerm_storage_account.datalake.name }
output "pause_command" {
  value = "az synapse sql pool pause --name sqldw --workspace-name ${azurerm_synapse_workspace.main.name} --resource-group ${azurerm_resource_group.synapse.name}"
}

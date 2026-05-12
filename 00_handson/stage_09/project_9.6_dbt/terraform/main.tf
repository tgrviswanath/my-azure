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

variable "resource_group_name" { default = "rg-dbt-lab" }
variable "location"            { default = "East US" }

resource "azurerm_resource_group" "dbt" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "dbt-synapse", stage = "09", env = "lab" }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ADLS Gen2 for Synapse workspace storage
resource "azurerm_storage_account" "synapse" {
  name                     = "stdbt${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.dbt.name
  location                 = azurerm_resource_group.dbt.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true

  tags = azurerm_resource_group.dbt.tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapse"
  storage_account_id = azurerm_storage_account.synapse.id
}

# Synapse Workspace
resource "azurerm_synapse_workspace" "dbt" {
  name                                 = "synapse-dbt-${random_string.suffix.result}"
  resource_group_name                  = azurerm_resource_group.dbt.name
  location                             = azurerm_resource_group.dbt.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id
  sql_administrator_login              = "sqladmin"
  sql_administrator_login_password     = "P@ssw0rd1234!"  # Use Key Vault in production

  identity {
    type = "SystemAssigned"
  }

  tags = azurerm_resource_group.dbt.tags
}

# Synapse Dedicated SQL Pool (DW100c — smallest, cheapest)
resource "azurerm_synapse_sql_pool" "sqldw" {
  name                 = "sqldw"
  synapse_workspace_id = azurerm_synapse_workspace.dbt.id
  sku_name             = "DW100c"
  create_mode          = "Default"

  # Auto-pause after 60 minutes of inactivity — CRITICAL for cost control
  auto_pause_delay_in_minutes = 60

  tags = azurerm_resource_group.dbt.tags
}

# Firewall rule to allow Azure services
resource "azurerm_synapse_firewall_rule" "allow_azure" {
  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.dbt.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# Firewall rule to allow your IP (replace with your actual IP)
resource "azurerm_synapse_firewall_rule" "allow_my_ip" {
  name                 = "AllowMyIP"
  synapse_workspace_id = azurerm_synapse_workspace.dbt.id
  start_ip_address     = "0.0.0.0"    # Replace with your IP
  end_ip_address       = "255.255.255.255"  # Replace with your IP
}

# Outputs
output "synapse_workspace_name" {
  value = azurerm_synapse_workspace.dbt.name
}

output "synapse_sql_endpoint" {
  description = "Use this in profiles.yml as 'server'"
  value       = azurerm_synapse_workspace.dbt.connectivity_endpoints["sql"]
}

output "synapse_sql_pool_name" {
  value = azurerm_synapse_sql_pool.sqldw.name
}

output "storage_account_name" {
  value = azurerm_storage_account.synapse.name
}

output "dbt_profiles_server" {
  description = "Server value for ~/.dbt/profiles.yml"
  value       = "${azurerm_synapse_workspace.dbt.name}.sql.azuresynapse.net"
}

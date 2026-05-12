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

variable "resource_group_name" { default = "rg-adf-etl-lab" }
variable "location"            { default = "East US" }
variable "adf_name"            { default = "adf-etl-lab" }

resource "azurerm_resource_group" "adf" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "adf-etl", stage = "09", env = "lab" }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ADLS Gen2 Storage Account
resource "azurerm_storage_account" "adls" {
  name                     = "stadls${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.adf.name
  location                 = azurerm_resource_group.adf.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true  # Hierarchical namespace = ADLS Gen2

  tags = azurerm_resource_group.adf.tags
}

# Storage containers
resource "azurerm_storage_container" "raw" {
  name                  = "raw"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "processed" {
  name                  = "processed"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "rejected" {
  name                  = "rejected"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

# Azure Data Factory
resource "azurerm_data_factory" "adf" {
  name                = var.adf_name
  location            = azurerm_resource_group.adf.location
  resource_group_name = azurerm_resource_group.adf.name

  identity {
    type = "SystemAssigned"
  }

  tags = azurerm_resource_group.adf.tags
}

# Grant ADF managed identity access to ADLS
resource "azurerm_role_assignment" "adf_storage" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

# Linked Service — ADLS Gen2 (using managed identity)
resource "azurerm_data_factory_linked_service_azure_blob_storage" "adls_source" {
  name              = "ls_adls_source"
  data_factory_id   = azurerm_data_factory.adf.id
  connection_string = azurerm_storage_account.adls.primary_connection_string

  depends_on = [azurerm_data_factory.adf]
}

# Linked Service — ADLS Gen2 for sink (processed container)
resource "azurerm_data_factory_linked_service_azure_blob_storage" "adls_sink" {
  name              = "ls_adls_sink"
  data_factory_id   = azurerm_data_factory.adf.id
  connection_string = azurerm_storage_account.adls.primary_connection_string

  depends_on = [azurerm_data_factory.adf]
}

# Pipeline — Copy orders CSV to Parquet
resource "azurerm_data_factory_pipeline" "copy_orders" {
  name            = "pl_copy_orders"
  data_factory_id = azurerm_data_factory.adf.id
  description     = "Copy orders CSV from raw container to Parquet in processed container"

  activities_json = jsonencode([
    {
      name = "CopyOrdersToParquet"
      type = "Copy"
      inputs = [{
        referenceName = "ds_orders_csv_source"
        type          = "DatasetReference"
      }]
      outputs = [{
        referenceName = "ds_orders_parquet_sink"
        type          = "DatasetReference"
      }]
      typeProperties = {
        source = {
          type = "DelimitedTextSource"
          storeSettings = {
            type      = "AzureBlobStorageReadSettings"
            recursive = false
          }
        }
        sink = {
          type = "ParquetSink"
          storeSettings = {
            type = "AzureBlobStorageWriteSettings"
          }
        }
        enableStaging = false
      }
    }
  ])

  depends_on = [azurerm_data_factory.adf]
}

# Synapse Workspace
resource "azurerm_synapse_workspace" "synapse" {
  name                                 = "synapse-etl-${random_string.suffix.result}"
  resource_group_name                  = azurerm_resource_group.adf.name
  location                             = azurerm_resource_group.adf.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id
  sql_administrator_login              = "sqladmin"
  sql_administrator_login_password     = "P@ssw0rd1234!"  # Use Key Vault in production

  identity {
    type = "SystemAssigned"
  }

  tags = azurerm_resource_group.adf.tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapse"
  storage_account_id = azurerm_storage_account.adls.id
}

# Synapse Dedicated SQL Pool (DW100c — smallest size)
resource "azurerm_synapse_sql_pool" "sqldw" {
  name                 = "sqldw"
  synapse_workspace_id = azurerm_synapse_workspace.synapse.id
  sku_name             = "DW100c"
  create_mode          = "Default"

  # Auto-pause after 60 minutes of inactivity
  auto_pause_delay_in_minutes = 60

  tags = azurerm_resource_group.adf.tags
}

# Outputs
output "adf_name" {
  value = azurerm_data_factory.adf.name
}

output "storage_account_name" {
  value = azurerm_storage_account.adls.name
}

output "synapse_workspace_name" {
  value = azurerm_synapse_workspace.synapse.name
}

output "synapse_sql_endpoint" {
  value = azurerm_synapse_workspace.synapse.connectivity_endpoints["sql"]
}

output "adf_managed_identity_id" {
  value = azurerm_data_factory.adf.identity[0].principal_id
}

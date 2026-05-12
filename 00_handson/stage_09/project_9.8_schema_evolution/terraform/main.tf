# Project 9.8 — Schema Evolution & Partitioning (Delta Lake on Databricks)

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "schema" {
  name     = "rg-schema-evolution"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-09" }
}

# ADLS Gen2 for Delta Lake storage
resource "azurerm_storage_account" "datalake" {
  name                     = "stadlschema${var.project}001"
  resource_group_name      = azurerm_resource_group.schema.name
  location                 = azurerm_resource_group.schema.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true  # Hierarchical namespace for ADLS Gen2
  tags                     = { Project = var.project }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "delta" {
  name               = "delta-lake"
  storage_account_id = azurerm_storage_account.datalake.id
}

# Databricks workspace
resource "azurerm_databricks_workspace" "main" {
  name                = "dbw-schema-${var.project}"
  resource_group_name = azurerm_resource_group.schema.name
  location            = azurerm_resource_group.schema.location
  sku                 = "standard"
  tags                = { Project = var.project }
}

# Allow Databricks to access ADLS Gen2
resource "azurerm_role_assignment" "dbw_storage" {
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_workspace.main.storage_account_identity[0].principal_id
}

output "databricks_url"    { value = "https://${azurerm_databricks_workspace.main.workspace_url}" }
output "storage_account"   { value = azurerm_storage_account.datalake.name }
output "delta_container"   { value = azurerm_storage_data_lake_gen2_filesystem.delta.name }

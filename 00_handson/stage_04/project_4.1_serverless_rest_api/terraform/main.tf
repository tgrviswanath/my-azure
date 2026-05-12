terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "api" {
  name     = "rg-serverless-api"
  location = "East US"
}

resource "azurerm_storage_account" "func" {
  name                     = "stfuncapi001"
  resource_group_name      = azurerm_resource_group.api.name
  location                 = azurerm_resource_group.api.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "func" {
  name                = "asp-serverless-api"
  resource_group_name = azurerm_resource_group.api.name
  location            = azurerm_resource_group.api.location
  os_type             = "Linux"
  sku_name            = "Y1"   # Consumption plan
}

resource "azurerm_linux_function_app" "api" {
  name                       = "func-serverless-api-001"
  resource_group_name        = azurerm_resource_group.api.name
  location                   = azurerm_resource_group.api.location
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key
  service_plan_id            = azurerm_service_plan.func.id

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    COSMOS_CONNECTION_STRING = azurerm_cosmosdb_account.main.primary_sql_connection_string
  }
}

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-serverless-api-001"
  location            = azurerm_resource_group.api.location
  resource_group_name = azurerm_resource_group.api.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities { name = "EnableServerless" }

  consistency_policy { consistency_level = "Session" }

  geo_location {
    location          = azurerm_resource_group.api.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "appdb"
  resource_group_name = azurerm_resource_group.api.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "items" {
  name                = "items"
  resource_group_name = azurerm_resource_group.api.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/id"
}

output "function_app_url" {
  value = "https://${azurerm_linux_function_app.api.default_hostname}/api"
}

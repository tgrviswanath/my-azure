terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "url" {
  name     = "rg-url-shortener"
  location = "East US"
}

resource "azurerm_cosmosdb_account" "url" {
  name                = "cosmos-url-shortener-001"
  location            = azurerm_resource_group.url.location
  resource_group_name = azurerm_resource_group.url.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  capabilities { name = "EnableServerless" }
  consistency_policy { consistency_level = "Session" }
  geo_location { location = azurerm_resource_group.url.location; failover_priority = 0 }
}

resource "azurerm_cosmosdb_sql_database" "url" {
  name                = "urldb"
  resource_group_name = azurerm_resource_group.url.name
  account_name        = azurerm_cosmosdb_account.url.name
}

resource "azurerm_cosmosdb_sql_container" "urls" {
  name                = "urls"
  resource_group_name = azurerm_resource_group.url.name
  account_name        = azurerm_cosmosdb_account.url.name
  database_name       = azurerm_cosmosdb_sql_database.url.name
  partition_key_path  = "/id"
}

resource "azurerm_storage_account" "func" {
  name                     = "stfuncurl001"
  resource_group_name      = azurerm_resource_group.url.name
  location                 = azurerm_resource_group.url.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "func" {
  name                = "asp-url-shortener"
  resource_group_name = azurerm_resource_group.url.name
  location            = azurerm_resource_group.url.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "url" {
  name                       = "func-url-shortener-001"
  resource_group_name        = azurerm_resource_group.url.name
  location                   = azurerm_resource_group.url.location
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key
  service_plan_id            = azurerm_service_plan.func.id
  site_config { application_stack { python_version = "3.11" } }
  app_settings = { COSMOS_CONNECTION_STRING = azurerm_cosmosdb_account.url.primary_sql_connection_string }
}

output "function_url" {
  value = "https://${azurerm_linux_function_app.url.default_hostname}/api"
}

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "durable" {
  name     = "rg-durable-functions"
  location = "East US"
}

resource "azurerm_storage_account" "func" {
  name                     = "stfuncdurable001"
  resource_group_name      = azurerm_resource_group.durable.name
  location                 = azurerm_resource_group.durable.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "func" {
  name                = "asp-durable-functions"
  resource_group_name = azurerm_resource_group.durable.name
  location            = azurerm_resource_group.durable.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "durable" {
  name                       = "func-durable-workflow-001"
  resource_group_name        = azurerm_resource_group.durable.name
  location                   = azurerm_resource_group.durable.location
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key
  service_plan_id            = azurerm_service_plan.func.id
  site_config { application_stack { python_version = "3.11" } }
}

output "function_url" {
  value = "https://${azurerm_linux_function_app.durable.default_hostname}/api"
}

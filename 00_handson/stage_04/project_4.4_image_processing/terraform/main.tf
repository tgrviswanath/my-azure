terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "img" {
  name     = "rg-image-processing"
  location = "East US"
}

resource "azurerm_storage_account" "main" {
  name                     = "stimgprocessing001"
  resource_group_name      = azurerm_resource_group.img.name
  location                 = azurerm_resource_group.img.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "uploads" {
  name                  = "uploads"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "processed" {
  name                  = "processed"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_service_plan" "func" {
  name                = "asp-image-processing"
  resource_group_name = azurerm_resource_group.img.name
  location            = azurerm_resource_group.img.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "img" {
  name                       = "func-image-processing-001"
  resource_group_name        = azurerm_resource_group.img.name
  location                   = azurerm_resource_group.img.location
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.func.id
  site_config { application_stack { python_version = "3.11" } }
  app_settings = { STORAGE_CONNECTION_STRING = azurerm_storage_account.main.primary_connection_string }
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

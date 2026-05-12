terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "sb" {
  name     = "rg-service-bus"
  location = "East US"
}

resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-microservices-001"
  location            = azurerm_resource_group.sb.location
  resource_group_name = azurerm_resource_group.sb.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "orders" {
  name         = "orders"
  namespace_id = azurerm_servicebus_namespace.main.id

  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 3
  lock_duration                        = "PT1M"
  default_message_ttl                  = "P1D"
}

resource "azurerm_storage_account" "func" {
  name                     = "stfuncsb001"
  resource_group_name      = azurerm_resource_group.sb.name
  location                 = azurerm_resource_group.sb.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "func" {
  name                = "asp-service-bus"
  resource_group_name = azurerm_resource_group.sb.name
  location            = azurerm_resource_group.sb.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "sb" {
  name                       = "func-service-bus-001"
  resource_group_name        = azurerm_resource_group.sb.name
  location                   = azurerm_resource_group.sb.location
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key
  service_plan_id            = azurerm_service_plan.func.id
  site_config { application_stack { python_version = "3.11" } }
  app_settings = {
    SERVICE_BUS_CONNECTION_STRING = azurerm_servicebus_namespace.main.default_primary_connection_string
  }
}

output "service_bus_connection_string" {
  value     = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive = true
}

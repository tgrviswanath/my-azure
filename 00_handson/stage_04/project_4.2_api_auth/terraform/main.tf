terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
    azuread = { source = "hashicorp/azuread"; version = "~> 2.0" }
  }
}

provider "azurerm" { features {} }
provider "azuread" {}

resource "azurerm_resource_group" "auth" {
  name     = "rg-api-auth"
  location = "East US"
}

# App Registration for the API
resource "azuread_application" "api" {
  display_name = "func-api-auth"

  app_role {
    allowed_member_types = ["User"]
    description          = "Admin role"
    display_name         = "Admin"
    enabled              = true
    id                   = "00000000-0000-0000-0000-000000000001"
    value                = "Admin"
  }
}

resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
}

resource "azurerm_storage_account" "func" {
  name                     = "stfuncauth001"
  resource_group_name      = azurerm_resource_group.auth.name
  location                 = azurerm_resource_group.auth.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "func" {
  name                = "asp-api-auth"
  resource_group_name = azurerm_resource_group.auth.name
  location            = azurerm_resource_group.auth.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "auth" {
  name                       = "func-api-auth-001"
  resource_group_name        = azurerm_resource_group.auth.name
  location                   = azurerm_resource_group.auth.location
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key
  service_plan_id            = azurerm_service_plan.func.id

  site_config {
    application_stack { python_version = "3.11" }
  }

  app_settings = {
    AZURE_TENANT_ID = data.azuread_client_config.current.tenant_id
    AZURE_CLIENT_ID = azuread_application.api.client_id
  }
}

data "azuread_client_config" "current" {}

output "function_url" {
  value = "https://${azurerm_linux_function_app.auth.default_hostname}/api"
}

output "app_client_id" {
  value = azuread_application.api.client_id
}

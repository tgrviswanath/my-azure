terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "acr" {
  name     = "rg-acr"
  location = "East US"
}

resource "azurerm_container_registry" "main" {
  name                = "acrhandson001"
  resource_group_name = azurerm_resource_group.acr.name
  location            = azurerm_resource_group.acr.location
  sku                 = "Basic"
  admin_enabled       = false
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

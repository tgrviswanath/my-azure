terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate001"
    container_name       = "tfstate"
    key                  = "main.tfstate"
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "app" {
  name     = "rg-remote-state-demo"
  location = "East US"
}

resource "azurerm_virtual_network" "app" {
  name                = "vnet-remote-state-demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
}

output "vnet_id" {
  value = azurerm_virtual_network.app.id
}

output "resource_group_name" {
  value = azurerm_resource_group.app.name
}

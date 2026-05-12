terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-terraform-state"
  location = "East US"
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "stterraformstate001"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

output "storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "container_name" {
  value = azurerm_storage_container.tfstate.name
}

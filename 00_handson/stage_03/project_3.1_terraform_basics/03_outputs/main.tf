terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "main" {
  name     = "rg-outputs-demo"
  location = "East US"
}

resource "azurerm_storage_account" "main" {
  name                     = "stoutputsdemo001"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_primary_endpoint" {
  description = "Primary blob endpoint"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "resource_group_id" {
  description = "Resource group ID"
  value       = azurerm_resource_group.main.id
}

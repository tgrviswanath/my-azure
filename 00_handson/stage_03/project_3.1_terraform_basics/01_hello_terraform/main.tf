terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "hello" {
  name     = "rg-hello-terraform"
  location = "East US"
  tags     = { managed_by = "terraform" }
}

output "resource_group_name" {
  value = azurerm_resource_group.hello.name
}

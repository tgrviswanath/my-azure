terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" { features {} }

# Data sources — read existing resources
data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "existing" {
  name = "rg-hello-terraform"
}

data "azurerm_client_config" "current" {}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "existing_rg_location" {
  value = data.azurerm_resource_group.existing.location
}

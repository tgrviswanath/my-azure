terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stterraformstateXXXXXX" # Set via TF_BACKEND_STORAGE_ACCOUNT env var
    container_name       = "tfstate"
    key                  = "project-3.5/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  # In CI/CD, authentication uses environment variables:
  # ARM_CLIENT_ID       = ${{ secrets.AZURE_CLIENT_ID }}
  # ARM_CLIENT_SECRET   = ${{ secrets.AZURE_CLIENT_SECRET }}
  # ARM_TENANT_ID       = ${{ secrets.AZURE_TENANT_ID }}
  # ARM_SUBSCRIPTION_ID = ${{ secrets.AZURE_SUBSCRIPTION_ID }}
}

variable "resource_group_name" {
  type    = string
  default = "rg-cicd-demo"
}

variable "location" {
  type    = string
  default = "eastus"
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    project    = "terraform-cicd"
    managed_by = "github-actions"
    deployed_at = timestamp()
  }

  lifecycle {
    ignore_changes = [tags["deployed_at"]]
  }
}

# Role assignment for the service principal (so it can manage resources)
data "azurerm_client_config" "current" {}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "deployed_by" {
  value = "GitHub Actions — service principal: ${data.azurerm_client_config.current.client_id}"
}

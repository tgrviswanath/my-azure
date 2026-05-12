terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.5.0"

  # ─────────────────────────────────────────────
  # Remote State Backend
  # Replace storage_account_name with your actual storage account name.
  # Run: python code/state_manager.py bootstrap --resource-group rg-tfstate ...
  # ─────────────────────────────────────────────
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stterraformstateXXXXXX" # Replace with actual name
    container_name       = "tfstate"
    key                  = "project-3.4/terraform.tfstate"
    # Authentication uses ARM_* environment variables or az login
    # For CI/CD, set:
    #   ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
  }
}

provider "azurerm" {
  features {}
}

# ─────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────

variable "resource_group_name" {
  type    = string
  default = "rg-remote-state-demo"
}

variable "location" {
  type    = string
  default = "eastus"
}

# ─────────────────────────────────────────────
# Demo Resources (to show state is stored remotely)
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "demo" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    project    = "remote-state-demo"
    managed_by = "terraform"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "demo" {
  name                     = "stremotestate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.demo.name
  location                 = azurerm_resource_group.demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  https_traffic_only_enabled = true
  tags                     = azurerm_resource_group.demo.tags
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "resource_group_name" {
  value = azurerm_resource_group.demo.name
}

output "storage_account_name" {
  value = azurerm_storage_account.demo.name
}

output "state_backend_info" {
  value = "State stored in: stterraformstateXXXXXX/tfstate/project-3.4/terraform.tfstate"
}

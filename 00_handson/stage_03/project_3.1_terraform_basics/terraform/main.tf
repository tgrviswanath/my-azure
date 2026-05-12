terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {}
  # Authentication: uses az login by default (Azure CLI credentials)
  # For CI/CD, set these environment variables instead:
  #   ARM_CLIENT_ID
  #   ARM_CLIENT_SECRET
  #   ARM_TENANT_ID
  #   ARM_SUBSCRIPTION_ID
}

# ─────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-terraform-basics"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"

  validation {
    condition     = contains(["eastus", "westus2", "westeurope", "eastasia"], var.location)
    error_message = "Location must be one of: eastus, westus2, westeurope, eastasia."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project    = "terraform-basics"
    managed_by = "terraform"
    environment = "learning"
  }
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ─────────────────────────────────────────────
# Storage Account
# ─────────────────────────────────────────────

# Storage account names must be globally unique, 3-24 chars, lowercase alphanumeric
resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "main" {
  name                     = "stterraform${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type

  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "resource_group_id" {
  description = "Resource Group resource ID"
  value       = azurerm_resource_group.main.id
}

output "resource_group_name" {
  description = "Resource Group name"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Storage Account name (globally unique)"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint URL"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_id" {
  description = "Storage Account resource ID"
  value       = azurerm_storage_account.main.id
}

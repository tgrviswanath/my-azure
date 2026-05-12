# Project 1.5 — Python Azure Automation
# Creates: Resource Group, Storage Account, Blob Containers for automation scripts

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

variable "location" {
  default = "East US"
}

variable "storage_account_name" {
  description = "Globally unique storage account name"
  default     = "pyautomation001"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "python-automation-rg"
  location = var.location
  tags = {
    project     = "python-automation"
    environment = "learning"
  }
}

# Storage Account for automation
resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable hierarchical namespace for Data Lake Gen2 (optional)
  is_hns_enabled = false

  tags = {
    project     = "python-automation"
    environment = "learning"
  }
}

# Container for uploads
resource "azurerm_storage_container" "uploads" {
  name                  = "uploads"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# Container for backups
resource "azurerm_storage_container" "backups" {
  name                  = "backups"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# Container for scripts/artifacts
resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

output "storage_account_name" {
  value       = azurerm_storage_account.storage.name
  description = "Storage account name for use in Python scripts"
}

output "storage_account_key" {
  value       = azurerm_storage_account.storage.primary_access_key
  sensitive   = true
  description = "Primary access key (use managed identity in production)"
}

output "blob_endpoint" {
  value       = azurerm_storage_account.storage.primary_blob_endpoint
  description = "Blob service endpoint URL"
}

output "containers" {
  value = [
    azurerm_storage_container.uploads.name,
    azurerm_storage_container.backups.name,
    azurerm_storage_container.scripts.name,
  ]
  description = "Created blob containers"
}

output "python_env_vars" {
  value = <<-EOT
    # Set these environment variables before running Python scripts:
    export AZURE_STORAGE_ACCOUNT="${azurerm_storage_account.storage.name}"
    export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  EOT
  description = "Environment variables to set for Python scripts"
}

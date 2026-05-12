terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ─── Variables ────────────────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-datalake-dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment tag (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project tag"
  type        = string
  default     = "datalake"
}

# ─── Random suffix for globally unique names ──────────────────────────────────

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ─── Resource Group ───────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.environment
    project     = var.project
    managed_by  = "terraform"
  }
}

# ─── ADLS Gen2 Storage Account ────────────────────────────────────────────────

resource "azurerm_storage_account" "datalake" {
  name                     = "adlsgen2${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable Hierarchical Namespace — this is what makes it ADLS Gen2
  is_hns_enabled = true

  # Security settings
  min_tls_version           = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled = true

  # Enable soft delete for blobs (7 days retention)
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }

  # Network rules — allow Azure services
  network_rules {
    default_action             = "Allow"
    bypass                     = ["AzureServices", "Logging", "Metrics"]
  }

  tags = {
    environment = var.environment
    project     = var.project
    managed_by  = "terraform"
  }
}

# ─── ADLS Gen2 Filesystems (Containers / Zones) ───────────────────────────────

resource "azurerm_storage_data_lake_gen2_filesystem" "raw" {
  name               = "raw"
  storage_account_id = azurerm_storage_account.datalake.id

  # Default ACL — owner has full access
  ace {
    type        = "user"
    permissions = "rwx"
  }
  ace {
    type        = "group"
    permissions = "r-x"
  }
  ace {
    type        = "other"
    permissions = "---"
  }

  properties = {
    zone        = "bronze"
    description = "Raw ingestion zone - immutable source of truth"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "processed" {
  name               = "processed"
  storage_account_id = azurerm_storage_account.datalake.id

  ace {
    type        = "user"
    permissions = "rwx"
  }
  ace {
    type        = "group"
    permissions = "r-x"
  }
  ace {
    type        = "other"
    permissions = "---"
  }

  properties = {
    zone        = "silver"
    description = "Processed zone - cleaned and typed data in Parquet"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "curated" {
  name               = "curated"
  storage_account_id = azurerm_storage_account.datalake.id

  ace {
    type        = "user"
    permissions = "rwx"
  }
  ace {
    type        = "group"
    permissions = "r-x"
  }
  ace {
    type        = "other"
    permissions = "---"
  }

  properties = {
    zone        = "gold"
    description = "Curated zone - business-ready aggregates for analytics"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "archive" {
  name               = "archive"
  storage_account_id = azurerm_storage_account.datalake.id

  ace {
    type        = "user"
    permissions = "rwx"
  }
  ace {
    type        = "group"
    permissions = "r--"
  }
  ace {
    type        = "other"
    permissions = "---"
  }

  properties = {
    zone        = "archive"
    description = "Archive zone - cold storage for data older than 90 days"
  }
}

# ─── Lifecycle Management Policy ──────────────────────────────────────────────

resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = azurerm_storage_account.datalake.id

  rule {
    name    = "archive-old-raw-data"
    enabled = true

    filters {
      prefix_match = ["raw/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        # Move to cool tier after 30 days
        tier_to_cool_after_days_since_modification_greater_than = 30
        # Move to archive tier after 90 days
        tier_to_archive_after_days_since_modification_greater_than = 90
        # Delete after 365 days
        delete_after_days_since_modification_greater_than = 365
      }
    }
  }

  rule {
    name    = "delete-old-processed-data"
    enabled = true

    filters {
      prefix_match = ["processed/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 60
        tier_to_archive_after_days_since_modification_greater_than = 180
      }
    }
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "storage_account_name" {
  description = "Name of the ADLS Gen2 storage account"
  value       = azurerm_storage_account.datalake.name
}

output "storage_account_id" {
  description = "Resource ID of the ADLS Gen2 storage account"
  value       = azurerm_storage_account.datalake.id
}

output "dfs_endpoint" {
  description = "DFS endpoint for ADLS Gen2 (use this for azure-storage-file-datalake)"
  value       = azurerm_storage_account.datalake.primary_dfs_endpoint
}

output "blob_endpoint" {
  description = "Blob endpoint for the storage account"
  value       = azurerm_storage_account.datalake.primary_blob_endpoint
}

output "raw_filesystem_id" {
  description = "Resource ID of the raw filesystem"
  value       = azurerm_storage_data_lake_gen2_filesystem.raw.id
}

output "processed_filesystem_id" {
  description = "Resource ID of the processed filesystem"
  value       = azurerm_storage_data_lake_gen2_filesystem.processed.id
}

output "curated_filesystem_id" {
  description = "Resource ID of the curated filesystem"
  value       = azurerm_storage_data_lake_gen2_filesystem.curated.id
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

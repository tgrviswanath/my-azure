# ============================================================
# Terraform Module: Storage Account
# Production-grade Azure Storage with lifecycle, versioning, firewall
# ============================================================

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.80" }
  }
}

variable "name"                { type = string; description = "Storage account name (3-24 chars, lowercase, no hyphens)" }
variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "sku"                 { type = string; default = "Standard_ZRS" }
variable "access_tier"         { type = string; default = "Hot" }
variable "enable_hns"          { type = bool;   default = false; description = "Enable hierarchical namespace (Data Lake Gen2)" }
variable "enable_versioning"   { type = bool;   default = false }
variable "soft_delete_days"    { type = number; default = 7 }
variable "allowed_subnet_ids"  { type = list(string); default = [] }
variable "allowed_ip_ranges"   { type = list(string); default = [] }
variable "tags"                { type = map(string); default = {} }

variable "containers" {
  type    = list(object({ name = string }))
  default = []
  description = "Blob containers to create"
}

variable "lifecycle_rules" {
  type = list(object({
    name        = string
    prefix      = string
    cool_days   = optional(number)
    archive_days = optional(number)
    delete_days  = optional(number)
  }))
  default = []
}

# ── Storage Account ───────────────────────────────────────────────────────────
resource "azurerm_storage_account" "this" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = split("_", var.sku)[0]
  account_replication_type = join("_", slice(split("_", var.sku), 1, length(split("_", var.sku))))
  account_kind             = "StorageV2"
  access_tier              = var.access_tier
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  is_hns_enabled                  = var.enable_hns
  tags                            = var.tags

  blob_properties {
    delete_retention_policy {
      days                     = max(var.soft_delete_days, 1)
      permanent_delete_enabled = false
    }
    container_delete_retention_policy {
      days = max(var.soft_delete_days, 1)
    }
    versioning_enabled  = var.enable_versioning
    change_feed_enabled = var.enable_versioning
  }

  network_rules {
    default_action             = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }
}

# ── Containers ────────────────────────────────────────────────────────────────
resource "azurerm_storage_container" "containers" {
  for_each              = { for c in var.containers : c.name => c }
  name                  = each.key
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

# ── Lifecycle Policy ──────────────────────────────────────────────────────────
resource "azurerm_storage_management_policy" "lifecycle" {
  count              = length(var.lifecycle_rules) > 0 ? 1 : 0
  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      name    = rule.value.name
      enabled = true
      filters {
        blob_types   = ["blockBlob"]
        prefix_match = [rule.value.prefix]
      }
      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = rule.value.cool_days
          tier_to_archive_after_days_since_modification_greater_than = rule.value.archive_days
          delete_after_days_since_modification_greater_than          = rule.value.delete_days
        }
      }
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "id"                   { value = azurerm_storage_account.this.id }
output "name"                 { value = azurerm_storage_account.this.name }
output "primary_blob_endpoint"{ value = azurerm_storage_account.this.primary_blob_endpoint }
output "primary_access_key"   { value = azurerm_storage_account.this.primary_access_key; sensitive = true }
output "primary_connection_string" { value = azurerm_storage_account.this.primary_connection_string; sensitive = true }

# Project 1.1 — Static Website on Azure Storage + CDN
# Creates: Resource Group, Storage Account (static website), CDN Profile, CDN Endpoint

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
  description = "Globally unique storage account name (3-24 chars, lowercase alphanumeric)"
  default     = "mystaticsite001"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "static-website-rg"
  location = var.location
  tags = {
    project     = "static-website"
    environment = "learning"
  }
}

# Storage Account
resource "azurerm_storage_account" "static_site" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable static website hosting
  static_website {
    index_document     = "index.html"
    error_404_document = "404.html"
  }

  # Allow public blob access for static website
  allow_nested_items_to_be_public = true

  tags = {
    project     = "static-website"
    environment = "learning"
  }
}

# CDN Profile
resource "azurerm_cdn_profile" "cdn" {
  name                = "static-site-cdn-profile"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard_Microsoft"

  tags = {
    project = "static-website"
  }
}

# CDN Endpoint — points to Storage static website
resource "azurerm_cdn_endpoint" "endpoint" {
  name                = "${var.storage_account_name}-endpoint"
  profile_name        = azurerm_cdn_profile.cdn.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  origin_host_header = azurerm_storage_account.static_site.primary_web_host

  origin {
    name      = "storage-origin"
    host_name = azurerm_storage_account.static_site.primary_web_host
  }

  # Enable compression for faster delivery
  is_compression_enabled = true
  content_types_to_compress = [
    "text/html",
    "text/css",
    "application/javascript",
    "application/json"
  ]

  tags = {
    project = "static-website"
  }
}

output "storage_web_endpoint" {
  value       = azurerm_storage_account.static_site.primary_web_endpoint
  description = "Direct Azure Storage static website URL"
}

output "cdn_endpoint_url" {
  value       = "https://${azurerm_cdn_endpoint.endpoint.host_name}"
  description = "CDN endpoint URL (globally cached)"
}

output "upload_command" {
  value       = "az storage blob upload-batch --account-name ${var.storage_account_name} --source ./code/website/ --destination '$web'"
  description = "Command to upload website files"
}

output "purge_command" {
  value       = "az cdn endpoint purge --name ${azurerm_cdn_endpoint.endpoint.name} --profile-name ${azurerm_cdn_profile.cdn.name} --resource-group ${azurerm_resource_group.rg.name} --content-paths '/*'"
  description = "Command to purge CDN cache after updates"
}

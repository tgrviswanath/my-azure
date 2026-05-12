# Project 1.3 — Azure AD RBAC & Identity Management
# Creates: Resource Group, User-Assigned Managed Identity, Role Assignments

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

variable "location" {
  default = "East US"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "iam-lab-rg"
  location = var.location
  tags = {
    project     = "iam-lab"
    environment = "learning"
  }
}

# Azure AD Security Groups
resource "azuread_group" "developers" {
  display_name     = "azure-lab-developers"
  mail_enabled     = false
  security_enabled = true
  description      = "Developers with Contributor access to lab resources"
}

resource "azuread_group" "readers" {
  display_name     = "azure-lab-readers"
  mail_enabled     = false
  security_enabled = true
  description      = "Read-only access to lab resources"
}

# User-Assigned Managed Identity
resource "azurerm_user_assigned_identity" "lab_identity" {
  name                = "lab-managed-identity"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# Role Assignment: Developers group → Contributor on resource group
resource "azurerm_role_assignment" "developers_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.developers.object_id
}

# Role Assignment: Readers group → Reader on resource group
resource "azurerm_role_assignment" "readers_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.readers.object_id
}

# Role Assignment: Managed Identity → Reader on resource group
resource "azurerm_role_assignment" "identity_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.lab_identity.principal_id
}

# Storage Account for managed identity demo
resource "azurerm_storage_account" "storage" {
  name                     = "iamlabstorage${substr(md5(azurerm_resource_group.rg.id), 0, 6)}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Role Assignment: Managed Identity → Storage Blob Data Reader
resource "azurerm_role_assignment" "identity_blob_reader" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.lab_identity.principal_id
}

output "resource_group_id" {
  value = azurerm_resource_group.rg.id
}

output "managed_identity_id" {
  value       = azurerm_user_assigned_identity.lab_identity.id
  description = "Resource ID of the user-assigned managed identity"
}

output "managed_identity_principal_id" {
  value       = azurerm_user_assigned_identity.lab_identity.principal_id
  description = "Principal ID (object ID) of the managed identity in Azure AD"
}

output "managed_identity_client_id" {
  value       = azurerm_user_assigned_identity.lab_identity.client_id
  description = "Client ID of the managed identity"
}

output "developers_group_id" {
  value = azuread_group.developers.object_id
}

output "readers_group_id" {
  value = azuread_group.readers.object_id
}

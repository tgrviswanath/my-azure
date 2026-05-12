# Project 8.1 — Azure Key Vault Integration

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
    azuread = { source = "hashicorp/azuread" version = "~> 2.0" }
  }
}

provider "azurerm" { features { key_vault { purge_soft_delete_on_destroy = false } } }
provider "azuread" {}

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "kv" {
  name     = "rg-key-vault"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-08" }
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "mi-app-${var.project}"
  resource_group_name = azurerm_resource_group.kv.name
  location            = azurerm_resource_group.kv.location
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project}-001"
  location                   = azurerm_resource_group.kv.location
  resource_group_name        = azurerm_resource_group.kv.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false  # Set true in production
  tags                       = { Project = var.project }
}

# Allow current user to manage secrets
resource "azurerm_role_assignment" "admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Allow managed identity to read secrets
resource "azurerm_role_assignment" "app_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Store sample secrets
resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = "ChangeMe123!"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.admin]
}

resource "azurerm_key_vault_secret" "api_key" {
  name         = "api-key"
  value        = "placeholder-rotate-immediately"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.admin]
}

output "key_vault_uri"    { value = azurerm_key_vault.main.vault_uri }
output "key_vault_name"   { value = azurerm_key_vault.main.name }
output "managed_identity" { value = azurerm_user_assigned_identity.app.client_id }

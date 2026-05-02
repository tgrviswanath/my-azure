# ============================================================
# Terraform Module: Key Vault
# Production Key Vault with RBAC, soft delete, network rules
# ============================================================

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.80" }
    random  = { source = "hashicorp/random";  version = "~> 3.5" }
  }
}

variable "name_prefix"         { type = string }
variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "sku"                 { type = string; default = "standard" }
variable "soft_delete_days"    { type = number; default = 7 }
variable "purge_protection"    { type = bool;   default = false }
variable "allowed_subnet_ids"  { type = list(string); default = [] }
variable "allowed_ip_ranges"   { type = list(string); default = [] }
variable "secrets"             { type = map(string); default = {}; sensitive = true }
variable "rbac_assignments"    {
  type = list(object({
    principal_id = string
    role         = string
  }))
  default = []
}
variable "tags" { type = map(string); default = {} }

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_key_vault" "this" {
  name                       = "${var.name_prefix}-${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.sku
  enable_rbac_authorization  = true
  soft_delete_retention_days = var.soft_delete_days
  purge_protection_enabled   = var.purge_protection
  tags                       = var.tags

  network_acls {
    default_action             = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }
}

# Deployer gets admin access
resource "azurerm_role_assignment" "deployer_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Secrets
resource "azurerm_key_vault_secret" "secrets" {
  for_each     = var.secrets
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_admin]
}

# RBAC assignments
resource "azurerm_role_assignment" "rbac" {
  for_each             = { for i, a in var.rbac_assignments : i => a }
  scope                = azurerm_key_vault.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}

output "id"   { value = azurerm_key_vault.this.id }
output "name" { value = azurerm_key_vault.this.name }
output "uri"  { value = azurerm_key_vault.this.vault_uri }

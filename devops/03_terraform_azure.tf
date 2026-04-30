# ============================================================
# Terraform — Azure Infrastructure
# Complete web application stack
# Usage:
#   terraform init
#   terraform plan -var-file="prod.tfvars"
#   terraform apply -var-file="prod.tfvars"
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Remote state in Azure Storage
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "myapp/prod/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────
variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "myapp"
}

variable "sql_admin_password" {
  description = "SQL admin password"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  prefix = "${var.app_name}-${var.environment}"
  common_tags = merge({
    Environment = var.environment
    Application = var.app_name
    ManagedBy   = "Terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }, var.tags)

  app_service_sku = {
    dev     = "B1"
    staging = "S2"
    prod    = "P2v3"
  }

  sql_sku = {
    dev     = "GP_Gen5_2"
    staging = "GP_Gen5_4"
    prod    = "BC_Gen5_8"
  }
}

# ── Data Sources ──────────────────────────────────────────────────────────────
data "azurerm_client_config" "current" {}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}-${var.location}"
  location = var.location
  tags     = local.common_tags
}

# ── Random suffix for globally unique names ───────────────────────────────────
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ── Log Analytics ─────────────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.common_tags
}

# ── Application Insights ──────────────────────────────────────────────────────
resource "azurerm_application_insights" "main" {
  name                = "ai-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.common_tags
}

# ── Key Vault ─────────────────────────────────────────────────────────────────
resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.prefix}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = var.environment == "prod" ? 90 : 7
  purge_protection_enabled   = var.environment == "prod"
  tags                       = local.common_tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

resource "azurerm_key_vault_secret" "sql_password" {
  name         = "SqlAdminPassword"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

# ── Virtual Network ───────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "appservice"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  service_endpoints = ["Microsoft.Sql", "Microsoft.Storage", "Microsoft.KeyVault"]
}

resource "azurerm_subnet" "db" {
  name                                          = "snet-db"
  resource_group_name                           = azurerm_resource_group.main.name
  virtual_network_name                          = azurerm_virtual_network.main.name
  address_prefixes                              = ["10.0.2.0/24"]
  private_endpoint_network_policies_enabled     = false
}

# ── Storage Account ───────────────────────────────────────────────────────────
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(local.prefix, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "ZRS" : "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  https_traffic_only_enabled = true
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                     = local.common_tags

  blob_properties {
    delete_retention_policy {
      days = var.environment == "prod" ? 30 : 7
    }
    container_delete_retention_policy {
      days = var.environment == "prod" ? 30 : 7
    }
    versioning_enabled = var.environment == "prod"
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.app.id]
  }
}

resource "azurerm_storage_container" "uploads" {
  name                  = "uploads"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ── SQL Server ────────────────────────────────────────────────────────────────
resource "azurerm_mssql_server" "main" {
  name                         = "sql-${local.prefix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  public_network_access_enabled = false
  tags                         = local.common_tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_mssql_database" "main" {
  name           = "${var.app_name}-db"
  server_id      = azurerm_mssql_server.main.id
  sku_name       = local.sql_sku[var.environment]
  zone_redundant = var.environment == "prod"
  tags           = local.common_tags
}

# ── App Service Plan ──────────────────────────────────────────────────────────
resource "azurerm_service_plan" "main" {
  name                = "asp-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = local.app_service_sku[var.environment]
  zone_balancing_enabled = var.environment == "prod"
  tags                = local.common_tags
}

# ── Web App ───────────────────────────────────────────────────────────────────
resource "azurerm_linux_web_app" "main" {
  name                = "app-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  virtual_network_subnet_id = azurerm_subnet.app.id
  tags                = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on         = var.environment != "dev"
    http2_enabled     = true
    minimum_tls_version = "1.2"
    ftps_state        = "Disabled"
    health_check_path = "/health"

    application_stack {
      node_version = "18-lts"
    }
  }

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.main.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    DATABASE_URL                          = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=DatabaseConnectionString)"
    STORAGE_ACCOUNT_NAME                  = azurerm_storage_account.main.name
    NODE_ENV                              = var.environment == "prod" ? "production" : var.environment
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
  }

  logs {
    application_logs {
      file_system_level = "Warning"
    }
    http_logs {
      retention_in_days = 7
    }
  }
}

# ── RBAC Assignments ──────────────────────────────────────────────────────────
# Terraform deployer gets KV admin
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Web app reads KV secrets
resource "azurerm_role_assignment" "webapp_kv_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Web app reads/writes storage
resource "azurerm_role_assignment" "webapp_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "web_app_url" {
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
  description = "Web application URL"
}

output "key_vault_name" {
  value       = azurerm_key_vault.main.name
  description = "Key Vault name"
}

output "storage_account_name" {
  value       = azurerm_storage_account.main.name
  description = "Storage account name"
}

output "sql_server_fqdn" {
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
  description = "SQL Server FQDN"
}

output "app_insights_connection_string" {
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
  description = "Application Insights connection string"
}

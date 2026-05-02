# ============================================================
# Terraform — Complete Azure Web Application Stack
# Uses modules from utils/terraform/modules/
# Deploy:
#   terraform init
#   terraform workspace new prod
#   terraform plan -var-file="environments/prod.tfvars"
#   terraform apply -var-file="environments/prod.tfvars"
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.80" }
    azuread = { source = "hashicorp/azuread"; version = "~> 2.45" }
    random  = { source = "hashicorp/random";  version = "~> 3.5" }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "webapp/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────
variable "environment"         { type = string }
variable "location"            { type = string; default = "eastus" }
variable "app_name"            { type = string }
variable "sql_admin_password"  { type = string; sensitive = true }
variable "acr_login_server"    { type = string; default = "" }
variable "tags"                { type = map(string); default = {} }

variable "app_service_config" {
  type = object({
    sku          = string
    always_on    = bool
    autoscale    = bool
    min_replicas = number
    max_replicas = number
  })
  default = {
    sku          = "B1"
    always_on    = false
    autoscale    = false
    min_replicas = 1
    max_replicas = 5
  }
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  prefix = "${var.app_name}-${var.environment}"
  common_tags = merge({
    Environment = var.environment
    Application = var.app_name
    ManagedBy   = "Terraform"
    Workspace   = terraform.workspace
  }, var.tags)
}

data "azurerm_client_config" "current" {}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}-${var.location}"
  location = var.location
  tags     = local.common_tags
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

resource "azurerm_application_insights" "main" {
  name                = "ai-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
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
  service_endpoints    = ["Microsoft.Sql", "Microsoft.Storage", "Microsoft.KeyVault"]

  delegation {
    name = "appservice"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "db" {
  name                                          = "snet-db"
  resource_group_name                           = azurerm_resource_group.main.name
  virtual_network_name                          = azurerm_virtual_network.main.name
  address_prefixes                              = ["10.0.2.0/24"]
  private_endpoint_network_policies_enabled     = false
}

# ── Key Vault (using module) ──────────────────────────────────────────────────
module "key_vault" {
  source = "./modules/key-vault"

  name_prefix         = "kv-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  soft_delete_days    = var.environment == "prod" ? 90 : 7
  purge_protection    = var.environment == "prod"
  allowed_subnet_ids  = [azurerm_subnet.app.id]
  tags                = local.common_tags

  secrets = {
    SqlAdminPassword = var.sql_admin_password
  }
}

# ── Storage Account ───────────────────────────────────────────────────────────
module "storage" {
  source = "./modules/storage-account"

  name                = "st${replace(local.prefix, "-", "")}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.environment == "prod" ? "Standard_ZRS" : "Standard_LRS"
  soft_delete_days    = var.environment == "prod" ? 30 : 7
  enable_versioning   = var.environment == "prod"
  allowed_subnet_ids  = [azurerm_subnet.app.id]
  tags                = local.common_tags

  containers = [
    { name = "uploads" },
    { name = "exports" },
  ]
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
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
  identity { type = "SystemAssigned" }
}

resource "azurerm_mssql_database" "main" {
  name           = "${var.app_name}-db"
  server_id      = azurerm_mssql_server.main.id
  sku_name       = var.environment == "prod" ? "GP_Gen5_4" : "Basic"
  zone_redundant = var.environment == "prod"
  tags           = local.common_tags
}

# ── App Service (using module) ────────────────────────────────────────────────
module "app_service" {
  source = "./modules/app-service"

  name                = "app-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  plan_sku            = var.app_service_config.sku
  always_on           = var.app_service_config.always_on
  vnet_subnet_id      = azurerm_subnet.app.id
  health_check_path   = "/health"
  tags                = local.common_tags

  app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    DATABASE_URL                          = "@Microsoft.KeyVault(VaultName=${module.key_vault.name};SecretName=DatabaseConnectionString)"
    STORAGE_ACCOUNT_NAME                  = module.storage.name
    NODE_ENV                              = var.environment == "prod" ? "production" : var.environment
  }

  autoscale = {
    enabled       = var.app_service_config.autoscale
    min_count     = var.app_service_config.min_replicas
    max_count     = var.app_service_config.max_replicas
    cpu_threshold = 70
  }
}

# ── RBAC: App → Key Vault ─────────────────────────────────────────────────────
resource "azurerm_role_assignment" "app_kv" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.app_service.principal_id
}

resource "azurerm_role_assignment" "app_storage" {
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.app_service.principal_id
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "web_app_url"              { value = module.app_service.url }
output "key_vault_name"           { value = module.key_vault.name }
output "storage_account_name"     { value = module.storage.name }
output "sql_server_fqdn"          { value = azurerm_mssql_server.main.fully_qualified_domain_name }
output "app_insights_conn_string" { value = azurerm_application_insights.main.connection_string; sensitive = true }
output "resource_group"           { value = azurerm_resource_group.main.name }

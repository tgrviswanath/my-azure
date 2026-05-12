# Project 10.5 — Production-grade Microservices Platform
# Composes all previous modules into a cohesive platform.

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location"       { default = "East US" }
variable "project"        { default = "handson" }
variable "environment"    { default = "prod" }
variable "sql_admin_pass" { sensitive = true; default = "YourPass123!" }
variable "alert_email"    { default = "admin@example.com" }

locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-platform"
  location = var.location
  tags     = local.common_tags
}

# ── AKS ───────────────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "platform" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  dns_prefix          = "aks-${local.name_prefix}"

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = "Standard_D2s_v3"
    only_critical_addons_enabled = true
  }

  identity { type = "SystemAssigned" }
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  tags = local.common_tags
}

# ── API Management ────────────────────────────────────────────────────────────
resource "azurerm_api_management" "platform" {
  name                = "apim-${local.name_prefix}-001"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  publisher_name      = "Handson Platform"
  publisher_email     = var.alert_email
  sku_name            = "Developer_1"  # Use Standard_1 for production
  tags                = local.common_tags
}

# ── Event Hubs ────────────────────────────────────────────────────────────────
resource "azurerm_eventhub_namespace" "platform" {
  name                = "evhns-${local.name_prefix}-001"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "Standard"
  capacity            = 1
  tags                = local.common_tags
}

resource "azurerm_eventhub" "orders" {
  name                = "orders-events"
  namespace_name      = azurerm_eventhub_namespace.platform.name
  resource_group_name = azurerm_resource_group.platform.name
  partition_count     = 4
  message_retention   = 1
}

# ── Redis Cache ───────────────────────────────────────────────────────────────
resource "azurerm_redis_cache" "platform" {
  name                = "redis-${local.name_prefix}-001"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  capacity            = 1
  family              = "C"
  sku_name            = "Standard"
  enable_non_ssl_port = false
  tags                = local.common_tags
}

# ── Azure SQL ─────────────────────────────────────────────────────────────────
resource "azurerm_mssql_server" "platform" {
  name                         = "sql-${local.name_prefix}-001"
  resource_group_name          = azurerm_resource_group.platform.name
  location                     = azurerm_resource_group.platform.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.sql_admin_pass
  tags                         = local.common_tags
}

resource "azurerm_mssql_database" "orders" {
  name      = "orders-db"
  server_id = azurerm_mssql_server.platform.id
  sku_name  = "S2"
}

# ── Application Insights ──────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "platform" {
  name                = "law-${local.name_prefix}"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "platform" {
  name                = "ai-${local.name_prefix}"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  workspace_id        = azurerm_log_analytics_workspace.platform.id
  application_type    = "web"
  tags                = local.common_tags
}

# ── Budget ────────────────────────────────────────────────────────────────────
data "azurerm_subscription" "current" {}

resource "azurerm_consumption_budget_subscription" "platform" {
  name            = "budget-platform"
  subscription_id = data.azurerm_subscription.current.id
  amount          = 800
  time_grain      = "Monthly"
  time_period { start_date = "2024-01-01T00:00:00Z" }
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }
}

output "aks_name"              { value = azurerm_kubernetes_cluster.platform.name }
output "apim_gateway_url"      { value = azurerm_api_management.platform.gateway_url }
output "event_hubs_namespace"  { value = azurerm_eventhub_namespace.platform.name }
output "redis_hostname"        { value = azurerm_redis_cache.platform.hostname }
output "sql_server_fqdn"       { value = azurerm_mssql_server.platform.fully_qualified_domain_name }
output "app_insights_key"      { value = azurerm_application_insights.platform.instrumentation_key; sensitive = true }

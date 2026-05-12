# Project 7.2 — Centralized Logging Platform
# Log Analytics Workspace + Managed Grafana

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "logging" {
  name     = "rg-centralized-logging"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-07" }
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}-central"
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = { Project = var.project }
}

resource "azurerm_dashboard_grafana" "main" {
  name                              = "grafana-${var.project}-001"
  resource_group_name               = azurerm_resource_group.logging.name
  location                          = azurerm_resource_group.logging.location
  grafana_major_version             = 10
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true

  azure_monitor_workspace_integrations {
    resource_id = azurerm_log_analytics_workspace.main.id
  }

  identity { type = "SystemAssigned" }
  tags = { Project = var.project }
}

# Allow Grafana to read from Log Analytics
resource "azurerm_role_assignment" "grafana_law" {
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id
}

output "law_workspace_id"  { value = azurerm_log_analytics_workspace.main.workspace_id }
output "law_resource_id"   { value = azurerm_log_analytics_workspace.main.id }
output "grafana_endpoint"  { value = azurerm_dashboard_grafana.main.endpoint }

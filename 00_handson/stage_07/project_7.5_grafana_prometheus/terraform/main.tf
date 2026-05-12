# Project 7.5 — Grafana + Prometheus Monitoring

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "monitoring" {
  name     = "rg-grafana-prometheus"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-07" }
}

# Azure Monitor Workspace (Managed Prometheus)
resource "azurerm_monitor_workspace" "prometheus" {
  name                = "prometheus-${var.project}"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location
  tags                = { Project = var.project }
}

# Azure Managed Grafana
resource "azurerm_dashboard_grafana" "main" {
  name                              = "grafana-${var.project}-001"
  resource_group_name               = azurerm_resource_group.monitoring.name
  location                          = azurerm_resource_group.monitoring.location
  grafana_major_version             = 10
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.prometheus.id
  }

  identity { type = "SystemAssigned" }
  tags = { Project = var.project }
}

# Allow Grafana to read from Prometheus workspace
resource "azurerm_role_assignment" "grafana_prometheus" {
  scope                = azurerm_monitor_workspace.prometheus.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id
}

output "grafana_endpoint"    { value = azurerm_dashboard_grafana.main.endpoint }
output "prometheus_endpoint" { value = azurerm_monitor_workspace.prometheus.query_endpoint }

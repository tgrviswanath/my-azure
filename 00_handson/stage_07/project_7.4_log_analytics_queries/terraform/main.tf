# Project 7.4 — Log Analytics Query Lab

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "queries" {
  name     = "rg-log-analytics-queries"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-07" }
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}-queries"
  location            = azurerm_resource_group.queries.location
  resource_group_name = azurerm_resource_group.queries.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = { Project = var.project }
}

# Storage account for NSG flow logs
resource "azurerm_storage_account" "flow_logs" {
  name                     = "stflowlogs${var.project}001"
  resource_group_name      = azurerm_resource_group.queries.name
  location                 = azurerm_resource_group.queries.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Action group for alerts
resource "azurerm_monitor_action_group" "alerts" {
  name                = "ag-${var.project}-queries"
  resource_group_name = azurerm_resource_group.queries.name
  short_name          = "queries"

  email_receiver {
    name          = "admin"
    email_address = "admin@example.com"
  }
}

# Scheduled query alert — failed deployments
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failed_deployments" {
  name                = "alert-failed-deployments"
  resource_group_name = azurerm_resource_group.queries.name
  location            = azurerm_resource_group.queries.location
  scopes              = [azurerm_log_analytics_workspace.main.id]
  description         = "Alert when more than 5 deployment failures in 15 minutes"
  severity            = 2
  enabled             = true

  window_duration      = "PT15M"
  evaluation_frequency = "PT5M"

  criteria {
    query                   = "AzureActivity | where ActivityStatusValue == 'Failure' and OperationNameValue contains 'deployments'"
    time_aggregation_method = "Count"
    threshold               = 5
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.alerts.id]
  }
}

output "workspace_id"   { value = azurerm_log_analytics_workspace.main.workspace_id }
output "workspace_name" { value = azurerm_log_analytics_workspace.main.name }

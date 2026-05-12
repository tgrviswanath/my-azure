# Project 7.3 — Application Insights Distributed Tracing

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "tracing" {
  name     = "rg-app-insights"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-07" }
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}-tracing"
  location            = azurerm_resource_group.tracing.location
  resource_group_name = azurerm_resource_group.tracing.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "main" {
  name                = "${var.project}-app-insights"
  location            = azurerm_resource_group.tracing.location
  resource_group_name = azurerm_resource_group.tracing.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = { Project = var.project }
}

output "connection_string"     { value = azurerm_application_insights.main.connection_string sensitive = true }
output "instrumentation_key"   { value = azurerm_application_insights.main.instrumentation_key sensitive = true }
output "app_insights_id"       { value = azurerm_application_insights.main.id }

# Project 10.3 — Cost Optimization Automation

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location"     { default = "East US" }
variable "project"      { default = "handson" }
variable "alert_email"  { default = "admin@example.com" }

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "cost" {
  name     = "rg-cost-optimization"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-10" }
}

# Automation account for runbooks
resource "azurerm_automation_account" "main" {
  name                = "aa-${var.project}-cost"
  location            = azurerm_resource_group.cost.location
  resource_group_name = azurerm_resource_group.cost.name
  sku_name            = "Basic"
  identity { type = "SystemAssigned" }
  tags = { Project = var.project }
}

# Allow automation to manage VMs
resource "azurerm_role_assignment" "automation_vm" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.main.identity[0].principal_id
}

# Budget with alerts
resource "azurerm_consumption_budget_subscription" "main" {
  name            = "budget-${var.project}"
  subscription_id = data.azurerm_subscription.current.id
  amount          = 500
  time_grain      = "Monthly"

  time_period {
    start_date = "2024-01-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }
}

output "automation_account" { value = azurerm_automation_account.main.name }
output "budget_name"        { value = azurerm_consumption_budget_subscription.main.name }

# Project 0.4 — Azure Cost Management & Billing
# Creates: Budget with 80%/100% alerts, Action Group for email notifications

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_subscription" "current" {}

variable "alert_email" {
  description = "Email address to receive budget alerts"
  type        = string
  default     = "your-email@example.com"
}

variable "budget_amount" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 20
}

# Resource Group for monitoring resources
resource "azurerm_resource_group" "monitoring_rg" {
  name     = "azure-monitoring-rg"
  location = "East US"
  tags = {
    project     = "billing-monitor"
    environment = "learning"
  }
}

# Action Group — defines who gets notified
resource "azurerm_monitor_action_group" "budget_alerts" {
  name                = "budget-alert-group"
  resource_group_name = azurerm_resource_group.monitoring_rg.name
  short_name          = "budgetalert"

  email_receiver {
    name          = "primary-email"
    email_address = var.alert_email
  }
}

# Monthly Budget with 80% and 100% alerts
resource "azurerm_consumption_budget_subscription" "monthly_budget" {
  name            = "monthly-lab-budget"
  subscription_id = data.azurerm_subscription.current.id

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = "2024-01-01T00:00:00Z"
    end_date   = "2025-12-31T00:00:00Z"
  }

  # Alert at 80% of budget
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"

    contact_emails = [var.alert_email]
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }

  # Alert at 100% of budget
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"

    contact_emails = [var.alert_email]
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }

  # Alert at 110% (forecasted overage)
  notification {
    enabled        = true
    threshold      = 110
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [var.alert_email]
  }
}

output "budget_name" {
  value = azurerm_consumption_budget_subscription.monthly_budget.name
}

output "budget_amount" {
  value = "${var.budget_amount} USD/month"
}

output "alert_email" {
  value = var.alert_email
}

output "subscription_id" {
  value = data.azurerm_subscription.current.id
}

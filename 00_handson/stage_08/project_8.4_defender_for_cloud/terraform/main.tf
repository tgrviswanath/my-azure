# Project 8.4 — Microsoft Defender for Cloud

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "security_email" { default = "security@example.com" }

resource "azurerm_security_center_subscription_pricing" "servers" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "sql" {
  tier          = "Standard"
  resource_type = "SqlServers"
}

resource "azurerm_security_center_subscription_pricing" "storage" {
  tier          = "Standard"
  resource_type = "StorageAccounts"
}

resource "azurerm_security_center_contact" "main" {
  email               = var.security_email
  phone               = "+1-555-0100"
  alert_notifications = true
  alerts_to_admins    = true
}

output "defender_status" { value = "Defender for Servers, SQL, and Storage enabled" }

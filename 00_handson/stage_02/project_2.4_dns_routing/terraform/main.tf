terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {
  type    = string
  default = "rg-dns-lab"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "dns_zone_name" {
  type        = string
  description = "Your domain name (e.g. yourdomain.com)"
  default     = "yourdomain.example"
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "dns-routing", managed_by = "terraform" }
}

# ─────────────────────────────────────────────
# Azure DNS Zone
# ─────────────────────────────────────────────

resource "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

# A record
resource "azurerm_dns_a_record" "www" {
  name                = "www"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = ["20.1.2.3"]
}

# CNAME pointing to Traffic Manager
resource "azurerm_dns_cname_record" "tm" {
  name                = "app"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 30
  record              = azurerm_traffic_manager_profile.main.fqdn
}

# TXT record for SPF
resource "azurerm_dns_txt_record" "spf" {
  name                = "@"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 3600

  record {
    value = "v=spf1 include:spf.protection.outlook.com -all"
  }
}

# ─────────────────────────────────────────────
# Public IPs for endpoints
# ─────────────────────────────────────────────

resource "azurerm_public_ip" "primary" {
  name                = "pip-primary"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "tm-endpoint-primary-${random_string.suffix.result}"
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_public_ip" "secondary" {
  name                = "pip-secondary"
  resource_group_name = azurerm_resource_group.main.name
  location            = "westus2"
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "tm-endpoint-secondary-${random_string.suffix.result}"
  tags                = azurerm_resource_group.main.tags
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ─────────────────────────────────────────────
# Traffic Manager Profile
# ─────────────────────────────────────────────

resource "azurerm_traffic_manager_profile" "main" {
  name                   = "tm-main"
  resource_group_name    = azurerm_resource_group.main.name
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "tm-main-${random_string.suffix.result}"
    ttl           = 30
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/health"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Traffic Manager Endpoints
# ─────────────────────────────────────────────

resource "azurerm_traffic_manager_azure_endpoint" "primary" {
  name               = "endpoint-primary"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target_resource_id = azurerm_public_ip.primary.id
  priority           = 1
  weight             = 100
  enabled            = true
}

resource "azurerm_traffic_manager_azure_endpoint" "secondary" {
  name               = "endpoint-secondary"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target_resource_id = azurerm_public_ip.secondary.id
  priority           = 2
  weight             = 100
  enabled            = true
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "dns_zone_name_servers" {
  description = "Update your domain registrar with these name servers"
  value       = azurerm_dns_zone.main.name_servers
}

output "traffic_manager_fqdn" {
  description = "Traffic Manager DNS name"
  value       = azurerm_traffic_manager_profile.main.fqdn
}

output "primary_endpoint_ip" {
  value = azurerm_public_ip.primary.ip_address
}

output "secondary_endpoint_ip" {
  value = azurerm_public_ip.secondary.ip_address
}

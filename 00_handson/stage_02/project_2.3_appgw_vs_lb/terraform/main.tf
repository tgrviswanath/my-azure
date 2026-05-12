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
  default = "rg-lb-comparison"
}

variable "location" {
  type    = string
  default = "eastus"
}

# ─────────────────────────────────────────────
# Resource Group + Networking
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "lb-comparison", managed_by = "terraform" }
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-comparison"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.2.0.0/16"]
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.2.0.0/24"]
}

resource "azurerm_subnet" "appgw_backend" {
  name                 = "subnet-appgw-backend"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.2.1.0/24"]
}

resource "azurerm_subnet" "lb_backend" {
  name                 = "subnet-lb-backend"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.2.2.0/24"]
}

# ─────────────────────────────────────────────
# Public IPs
# ─────────────────────────────────────────────

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_public_ip" "lb" {
  name                = "pip-lb"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Application Gateway (L7)
# ─────────────────────────────────────────────

locals {
  appgw_backend_pool  = "appgw-backend-pool"
  appgw_frontend_port = "appgw-frontend-port"
  appgw_frontend_ip   = "appgw-frontend-ip"
  appgw_http_settings = "appgw-http-settings"
  appgw_listener      = "appgw-listener"
  appgw_rule          = "appgw-rule"
  appgw_probe         = "appgw-probe"
  api_backend_pool    = "api-backend-pool"
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-comparison"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = local.appgw_frontend_port
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Default backend pool (web)
  backend_address_pool {
    name = local.appgw_backend_pool
  }

  # API backend pool
  backend_address_pool {
    name = local.api_backend_pool
  }

  backend_http_settings {
    name                  = local.appgw_http_settings
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = local.appgw_probe
  }

  probe {
    name                = local.appgw_probe
    protocol            = "Http"
    path                = "/health"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = local.appgw_listener
    frontend_ip_configuration_name = local.appgw_frontend_ip
    frontend_port_name             = local.appgw_frontend_port
    protocol                       = "Http"
  }

  # Path-based routing rule
  url_path_map {
    name                               = "url-path-map"
    default_backend_address_pool_name  = local.appgw_backend_pool
    default_backend_http_settings_name = local.appgw_http_settings

    path_rule {
      name                       = "api-rule"
      paths                      = ["/api/*"]
      backend_address_pool_name  = local.api_backend_pool
      backend_http_settings_name = local.appgw_http_settings
    }
  }

  request_routing_rule {
    name               = local.appgw_rule
    rule_type          = "PathBasedRouting"
    http_listener_name = local.appgw_listener
    url_path_map_name  = "url-path-map"
    priority           = 100
  }

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Azure Load Balancer (L4)
# ─────────────────────────────────────────────

resource "azurerm_lb" "main" {
  name                = "lb-comparison"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "lb-frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "lb-backend-pool"
}

resource "azurerm_lb_probe" "http" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "lb-http-probe"
  protocol        = "Http"
  port            = 80
  request_path    = "/health"
}

resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "lb-http-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "lb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.http.id
  enable_tcp_reset               = true
  idle_timeout_in_minutes        = 4
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "appgw_public_ip" {
  description = "Application Gateway public IP"
  value       = azurerm_public_ip.appgw.ip_address
}

output "lb_public_ip" {
  description = "Load Balancer public IP"
  value       = azurerm_public_ip.lb.ip_address
}

output "appgw_id" {
  value = azurerm_application_gateway.main.id
}

output "lb_id" {
  value = azurerm_lb.main.id
}

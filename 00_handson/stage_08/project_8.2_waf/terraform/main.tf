# Project 8.2 — WAF Application Protection

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "waf" {
  name     = "rg-waf"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-08" }
}

resource "azurerm_log_analytics_workspace" "waf" {
  name                = "law-${var.project}-waf"
  location            = azurerm_resource_group.waf.location
  resource_group_name = azurerm_resource_group.waf.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_virtual_network" "waf" {
  name                = "vnet-waf"
  resource_group_name = azurerm_resource_group.waf.name
  location            = azurerm_resource_group.waf.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.waf.name
  virtual_network_name = azurerm_virtual_network.waf.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw"
  resource_group_name = azurerm_resource_group.waf.name
  location            = azurerm_resource_group.waf.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_web_application_firewall_policy" "main" {
  name                = "waf-policy-${var.project}"
  resource_group_name = azurerm_resource_group.waf.name
  location            = azurerm_resource_group.waf.location

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-waf-${var.project}"
  resource_group_name = azurerm_resource_group.waf.name
  location            = azurerm_resource_group.waf.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.main.id

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port { name = "http"; port = 80 }

  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool { name = "backend-pool" }

  backend_http_settings {
    name                  = "backend-http"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "backend-http"
    priority                   = 100
  }
}

output "app_gateway_ip"   { value = azurerm_public_ip.appgw.ip_address }
output "waf_policy_name"  { value = azurerm_web_application_firewall_policy.main.name }

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

# ─────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────

variable "resource_group_name" {
  type    = string
  default = "rg-multitier"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "sql_admin_username" {
  type    = string
  default = "sqladmin"
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

variable "vmss_admin_username" {
  type    = string
  default = "azureuser"
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    project    = "multi-tier-app"
    managed_by = "terraform"
  }
}

# ─────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-multitier"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.1.0.0/16"]
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]
  service_endpoints    = ["Microsoft.Sql"]
}

resource "azurerm_subnet" "db" {
  name                 = "subnet-db"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.2.0/24"]
}

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Application Gateway
# ─────────────────────────────────────────────

locals {
  appgw_backend_pool_name  = "appgw-backend-pool"
  appgw_frontend_port_name = "appgw-frontend-port"
  appgw_frontend_ip_name   = "appgw-frontend-ip"
  appgw_http_setting_name  = "appgw-http-setting"
  appgw_listener_name      = "appgw-listener"
  appgw_rule_name          = "appgw-routing-rule"
  appgw_probe_name         = "appgw-health-probe"
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-main"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = local.appgw_frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = local.appgw_backend_pool_name
  }

  backend_http_settings {
    name                  = local.appgw_http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = local.appgw_probe_name
  }

  probe {
    name                = local.appgw_probe_name
    protocol            = "Http"
    path                = "/health"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = local.appgw_listener_name
    frontend_ip_configuration_name = local.appgw_frontend_ip_name
    frontend_port_name             = local.appgw_frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.appgw_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.appgw_listener_name
    backend_address_pool_name  = local.appgw_backend_pool_name
    backend_http_settings_name = local.appgw_http_setting_name
    priority                   = 100
  }

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# VM Scale Set
# ─────────────────────────────────────────────

resource "azurerm_linux_virtual_machine_scale_set" "web" {
  name                = "vmss-web"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard_B2s"
  instances           = 2
  admin_username      = var.vmss_admin_username
  upgrade_mode        = "Automatic"

  admin_ssh_key {
    username   = var.vmss_admin_username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic-vmss-web"
    primary = true

    ip_configuration {
      name                                         = "ipconfig-vmss"
      primary                                      = true
      subnet_id                                    = azurerm_subnet.web.id
      application_gateway_backend_address_pool_ids = [
        tolist(azurerm_application_gateway.main.backend_address_pool)[0].id
      ]
    }
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
    mkdir -p /var/www/html
    echo "OK" > /var/www/html/health
    systemctl enable nginx
    systemctl start nginx
  EOF
  )

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_monitor_autoscale_setting" "vmss_web" {
  name                = "autoscale-vmss-web"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.web.id

  profile {
    name = "default"

    capacity {
      default = 2
      minimum = 2
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Azure SQL
# ─────────────────────────────────────────────

resource "azurerm_mssql_server" "main" {
  name                         = "sql-server-multitier-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password

  tags = azurerm_resource_group.main.tags
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_mssql_database" "app" {
  name         = "db-app"
  server_id    = azurerm_mssql_server.main.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  sku_name     = "S1"

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_mssql_virtual_network_rule" "web_subnet" {
  name      = "allow-web-subnet"
  server_id = azurerm_mssql_server.main.id
  subnet_id = azurerm_subnet.web.id
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "appgw_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "vmss_name" {
  value = azurerm_linux_virtual_machine_scale_set.web.name
}

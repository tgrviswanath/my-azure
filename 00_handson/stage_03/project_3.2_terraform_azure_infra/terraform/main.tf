terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {}
}

# ─────────────────────────────────────────────
# variables.tf (inline)
# ─────────────────────────────────────────────

variable "resource_group_name" {
  type    = string
  default = "rg-full-infra"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "vm_admin_username" {
  type    = string
  default = "azureuser"
}

variable "sql_admin_username" {
  type    = string
  default = "sqladmin"
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    project    = "full-infra"
    managed_by = "terraform"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ─────────────────────────────────────────────
# Virtual Network
# ─────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-full-infra"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Sql"]
}

resource "azurerm_subnet" "db" {
  name                 = "subnet-db"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

# ─────────────────────────────────────────────
# NSGs
# ─────────────────────────────────────────────

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_network_security_group" "db" {
  name                = "nsg-db"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "Allow-SQL-From-Web"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
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

resource "azurerm_public_ip" "vm" {
  name                = "pip-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Application Gateway
# ─────────────────────────────────────────────

resource "azurerm_application_gateway" "main" {
  name                = "appgw-full-infra"
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
    name = "frontend-port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = "backend-pool"
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "frontend-port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# VM
# ─────────────────────────────────────────────

resource "azurerm_network_interface" "vm" {
  name                = "nic-vm-web"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_linux_virtual_machine" "web" {
  name                = "vm-web"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2s"
  admin_username      = var.vm_admin_username

  network_interface_ids = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    echo "<h1>Hello from vm-web</h1>" > /var/www/html/index.html
    echo "OK" > /var/www/html/health
    systemctl enable nginx && systemctl start nginx
  EOF
  )

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Azure SQL
# ─────────────────────────────────────────────

resource "azurerm_mssql_server" "main" {
  name                         = "sql-full-infra-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  tags                         = azurerm_resource_group.main.tags
}

resource "azurerm_mssql_database" "app" {
  name      = "db-app"
  server_id = azurerm_mssql_server.main.id
  sku_name  = "S1"

  lifecycle {
    prevent_destroy = false  # Set to true in production
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_mssql_virtual_network_rule" "web" {
  name      = "allow-web-subnet"
  server_id = azurerm_mssql_server.main.id
  subnet_id = azurerm_subnet.web.id
}

# ─────────────────────────────────────────────
# outputs.tf (inline)
# ─────────────────────────────────────────────

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "appgw_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "vm_public_ip" {
  value = azurerm_public_ip.vm.ip_address
}

output "sql_server_name" {
  value = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

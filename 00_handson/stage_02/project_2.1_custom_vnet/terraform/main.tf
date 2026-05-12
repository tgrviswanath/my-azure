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
  description = "Name of the resource group"
  type        = string
  default     = "rg-vnet-lab"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = string
  default     = "10.0.0.0/16"
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "vnet-lab"
    environment = "learning"
    managed_by  = "terraform"
  }
}

# ─────────────────────────────────────────────
# Virtual Network
# ─────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-main"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_address_space]

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Subnets
# ─────────────────────────────────────────────

resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "app" {
  name                 = "subnet-app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "db" {
  name                 = "subnet-db"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

# ─────────────────────────────────────────────
# Network Security Groups
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

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "Allow-From-Web"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
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

resource "azurerm_network_security_group" "db" {
  name                = "nsg-db"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "Allow-SQL-From-App"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "10.0.2.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
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

# ─────────────────────────────────────────────
# NSG Associations
# ─────────────────────────────────────────────

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

# ─────────────────────────────────────────────
# Public IP for NAT Gateway
# ─────────────────────────────────────────────

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-gateway"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# NAT Gateway
# ─────────────────────────────────────────────

resource "azurerm_nat_gateway" "main" {
  name                    = "nat-gateway-main"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "db" {
  subnet_id      = azurerm_subnet.db.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

# ─────────────────────────────────────────────
# Route Tables
# ─────────────────────────────────────────────

resource "azurerm_route_table" "app" {
  name                = "rt-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  route {
    name           = "route-to-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_route_table" "db" {
  name                = "rt-db"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  route {
    name           = "route-block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_subnet_route_table_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  route_table_id = azurerm_route_table.app.id
}

resource "azurerm_subnet_route_table_association" "db" {
  subnet_id      = azurerm_subnet.db.id
  route_table_id = azurerm_route_table.db.id
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "vnet_id" {
  description = "VNet resource ID"
  value       = azurerm_virtual_network.main.id
}

output "subnet_web_id" {
  description = "Web subnet ID"
  value       = azurerm_subnet.web.id
}

output "subnet_app_id" {
  description = "App subnet ID"
  value       = azurerm_subnet.app.id
}

output "subnet_db_id" {
  description = "DB subnet ID"
  value       = azurerm_subnet.db.id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway public IP address"
  value       = azurerm_public_ip.nat.ip_address
}

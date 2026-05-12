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
  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}

variable "resource_group_name" {
  type    = string
  default = "rg-chaos-lab"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
  default   = "ChaosP@ssw0rd123"
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "chaos-lab", managed_by = "terraform" }
}

# ─────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-chaos"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.3.0.0/16"]
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_subnet" "vms" {
  name                 = "subnet-vms"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.3.1.0/24"]
}

resource "azurerm_network_security_group" "chaos" {
  name                = "nsg-chaos"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_subnet_network_security_group_association" "vms" {
  subnet_id                 = azurerm_subnet.vms.id
  network_security_group_id = azurerm_network_security_group.chaos.id
}

# ─────────────────────────────────────────────
# VM
# ─────────────────────────────────────────────

resource "azurerm_public_ip" "vm" {
  name                = "pip-chaos-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-chaos-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.vms.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_linux_virtual_machine" "target" {
  name                = "vm-chaos-target"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"

  network_interface_ids = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = "azureuser"
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
    echo "OK" > /var/www/html/health
    systemctl enable nginx && systemctl start nginx
  EOF
  )

  tags = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Azure SQL
# ─────────────────────────────────────────────

resource "azurerm_mssql_server" "chaos" {
  name                         = "sql-chaos-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.sql_admin_password
  tags                         = azurerm_resource_group.main.tags
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_mssql_database" "chaos" {
  name      = "db-chaos"
  server_id = azurerm_mssql_server.chaos.id
  sku_name  = "Basic"
  tags      = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "vm_public_ip" {
  value = azurerm_public_ip.vm.ip_address
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.target.name
}

output "nsg_name" {
  value = azurerm_network_security_group.chaos.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.chaos.name
}

output "sql_database_name" {
  value = azurerm_mssql_database.chaos.name
}

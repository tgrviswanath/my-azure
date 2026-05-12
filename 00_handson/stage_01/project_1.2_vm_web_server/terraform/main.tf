# Project 1.2 — Linux Web Server on Azure VM
# Creates: Resource Group, VNet, Subnet, NSG (80/443/22), Public IP, NIC, B2s Ubuntu VM

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

variable "location" {
  default = "East US"
}

variable "admin_username" {
  default = "azureuser"
}

variable "ssh_public_key_path" {
  default = "~/.ssh/azure_lab.pub"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "vm-web-server-rg"
  location = var.location
  tags = {
    project     = "vm-web-server"
    environment = "learning"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vm-web-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "vm-web-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "vm-web-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Public IP
resource "azurerm_public_ip" "pip" {
  name                = "vm-web-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

# Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "vm-web-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Linux Virtual Machine — B2s with Nginx via cloud-init
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-web-server"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # cloud-init: install and configure Nginx on first boot
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y nginx

    # Enable and start Nginx
    systemctl enable nginx
    systemctl start nginx

    # Create custom landing page
    PUBLIC_IP=$(curl -s ifconfig.me || echo "unknown")
    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
    <head><title>Azure VM Web Server</title></head>
    <body style="font-family:Arial;background:#0078d4;color:white;text-align:center;padding:50px">
      <h1>Azure VM Web Server</h1>
      <p>Running on: $(hostname)</p>
      <p>Public IP: $PUBLIC_IP</p>
      <p>Nginx version: $(nginx -v 2>&1)</p>
    </body>
    </html>
    HTML

    # Configure reverse proxy
    cat > /etc/nginx/sites-available/default <<NGINX
    server {
        listen 80 default_server;
        root /var/www/html;
        index index.html;

        location / {
            try_files \$uri \$uri/ =404;
        }

        location /api/ {
            proxy_pass http://localhost:8080/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
    NGINX

    nginx -t && systemctl reload nginx
  EOF
  )

  tags = {
    project     = "vm-web-server"
    environment = "learning"
  }
}

output "public_ip" {
  value       = azurerm_public_ip.pip.ip_address
  description = "Public IP address of the web server"
}

output "ssh_command" {
  value       = "ssh -i ~/.ssh/azure_lab ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
  description = "SSH command to connect"
}

output "http_url" {
  value       = "http://${azurerm_public_ip.pip.ip_address}"
  description = "HTTP URL to test the web server"
}

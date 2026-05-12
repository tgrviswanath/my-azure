variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "subnet_id" { type = string }
variable "vm_size" { type = string; default = "Standard_B1s" }
variable "vm_count" { type = number; default = 1 }
variable "admin_username" { type = string; default = "azureuser" }
variable "tags" { type = map(string); default = {} }

resource "azurerm_public_ip" "vm" {
  count               = var.vm_count
  name                = "pip-vm-${var.environment}-${count.index}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "vm" {
  count               = var.vm_count
  name                = "nic-vm-${var.environment}-${count.index}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm[count.index].id
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.vm_count
  name                = "vm-${var.environment}-${count.index}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.vm[count.index].id]

  admin_ssh_key {
    username   = var.admin_username
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
    apt-get update -y && apt-get install -y nginx
    echo "<h1>${var.environment} - vm-${count.index}</h1>" > /var/www/html/index.html
    echo "OK" > /var/www/html/health
    systemctl enable nginx && systemctl start nginx
  EOF
  )

  tags = var.tags
}

output "vm_ids" { value = azurerm_linux_virtual_machine.vm[*].id }
output "public_ips" { value = azurerm_public_ip.vm[*].ip_address }
output "private_ips" { value = azurerm_network_interface.vm[*].private_ip_address }

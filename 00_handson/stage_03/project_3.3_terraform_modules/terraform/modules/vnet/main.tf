variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "vnet_address_space" { type = string; default = "10.0.0.0/16" }
variable "tags" { type = map(string); default = {} }

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Sql"]
}

resource "azurerm_subnet" "db" {
  name                 = "subnet-db"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

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
    name                       = "Allow-SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

output "vnet_id" { value = azurerm_virtual_network.main.id }
output "web_subnet_id" { value = azurerm_subnet.web.id }
output "db_subnet_id" { value = azurerm_subnet.db.id }
output "nsg_web_id" { value = azurerm_network_security_group.web.id }

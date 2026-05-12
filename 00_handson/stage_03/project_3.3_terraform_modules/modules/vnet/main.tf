variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "address_space" { type = list(string) }
variable "subnets" {
  type = map(string)
  description = "Map of subnet name to CIDR"
}
variable "tags" { type = map(string) default = {} }

resource "azurerm_virtual_network" "this" {
  name                = var.name
  address_space       = var.address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each             = var.subnets
  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]
}

output "vnet_id" { value = azurerm_virtual_network.this.id }
output "subnet_ids" { value = { for k, v in azurerm_subnet.this : k => v.id } }

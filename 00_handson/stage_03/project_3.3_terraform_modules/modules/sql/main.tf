variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "admin_password" { type = string; sensitive = true }
variable "sku_name" { type = string; default = "Basic" }
variable "tags" { type = map(string); default = {} }

resource "azurerm_mssql_server" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.admin_password
  tags                         = var.tags
}

resource "azurerm_mssql_database" "this" {
  name      = "appdb"
  server_id = azurerm_mssql_server.this.id
  sku_name  = var.sku_name
}

output "server_fqdn" { value = azurerm_mssql_server.this.fully_qualified_domain_name }

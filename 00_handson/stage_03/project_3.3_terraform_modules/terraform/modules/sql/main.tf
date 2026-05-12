variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "suffix" { type = string }
variable "sku_name" { type = string; default = "Basic" }
variable "admin_username" { type = string; default = "sqladmin" }
variable "admin_password" { type = string; sensitive = true }
variable "allowed_subnet_id" { type = string }
variable "tags" { type = map(string); default = {} }

resource "azurerm_mssql_server" "main" {
  name                         = "sql-${var.environment}-${var.suffix}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
  tags                         = var.tags
}

resource "azurerm_mssql_database" "app" {
  name      = "db-app-${var.environment}"
  server_id = azurerm_mssql_server.main.id
  sku_name  = var.sku_name
  tags      = var.tags
}

resource "azurerm_mssql_virtual_network_rule" "allow_web" {
  name      = "allow-web-subnet"
  server_id = azurerm_mssql_server.main.id
  subnet_id = var.allowed_subnet_id
}

output "server_id" { value = azurerm_mssql_server.main.id }
output "server_fqdn" { value = azurerm_mssql_server.main.fully_qualified_domain_name }
output "database_id" { value = azurerm_mssql_database.app.id }

# Project 1.4 — Azure SQL Database
# Creates: Resource Group, SQL Server, SQL Database, Firewall Rules

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

variable "sql_admin_username" {
  description = "SQL Server administrator username"
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
  default     = "YourPass123!"  # Change this in production!
}

variable "my_ip_address" {
  description = "Your public IP address for firewall rule"
  default     = "0.0.0.0"  # Replace with your actual IP
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "azure-sql-lab-rg"
  location = var.location
  tags = {
    project     = "azure-sql-lab"
    environment = "learning"
  }
}

# SQL Server (logical server)
resource "azurerm_mssql_server" "sql_server" {
  name                         = "sql-lab-server-${substr(md5(azurerm_resource_group.rg.id), 0, 8)}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password

  tags = {
    project     = "azure-sql-lab"
    environment = "learning"
  }
}

# SQL Database — Basic tier (cheapest, good for learning)
resource "azurerm_mssql_database" "database" {
  name      = "labdb"
  server_id = azurerm_mssql_server.sql_server.id
  sku_name  = "Basic"

  # Backup retention
  short_term_retention_policy {
    retention_days           = 7
    backup_interval_in_hours = 12
  }

  tags = {
    project     = "azure-sql-lab"
    environment = "learning"
  }
}

# Firewall Rule — Allow your IP
resource "azurerm_mssql_firewall_rule" "allow_my_ip" {
  name             = "AllowMyIP"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = var.my_ip_address
  end_ip_address   = var.my_ip_address
}

# Firewall Rule — Allow Azure services (0.0.0.0 is the Azure magic IP)
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

output "sql_server_fqdn" {
  value       = azurerm_mssql_server.sql_server.fully_qualified_domain_name
  description = "Fully qualified domain name of the SQL Server"
}

output "database_name" {
  value = azurerm_mssql_database.database.name
}

output "connection_string" {
  value = join(";", [
    "Server=tcp:${azurerm_mssql_server.sql_server.fully_qualified_domain_name},1433",
    "Initial Catalog=${azurerm_mssql_database.database.name}",
    "Persist Security Info=False",
    "User ID=${var.sql_admin_username}",
    "Password=${var.sql_admin_password}",
    "MultipleActiveResultSets=False",
    "Encrypt=True",
    "TrustServerCertificate=False",
    "Connection Timeout=30"
  ])
  sensitive   = true
  description = "ADO.NET connection string"
}

output "sqlcmd_command" {
  value       = "sqlcmd -S ${azurerm_mssql_server.sql_server.fully_qualified_domain_name} -U ${var.sql_admin_username} -P '${var.sql_admin_password}' -d ${azurerm_mssql_database.database.name}"
  sensitive   = true
  description = "sqlcmd connection command"
}

# Project 10.2 — Disaster Recovery Architecture

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "project"        { default = "handson" }
variable "sql_admin_user" { default = "sqladmin" }
variable "sql_admin_pass" { default = "YourPass123!"; sensitive = true }

resource "azurerm_resource_group" "primary" {
  name     = "rg-dr-primary"
  location = "East US"
  tags     = { Project = var.project, Role = "primary" }
}

resource "azurerm_resource_group" "secondary" {
  name     = "rg-dr-secondary"
  location = "West US"
  tags     = { Project = var.project, Role = "secondary" }
}

# Primary SQL Server
resource "azurerm_mssql_server" "primary" {
  name                         = "sql-primary-${var.project}-001"
  resource_group_name          = azurerm_resource_group.primary.name
  location                     = azurerm_resource_group.primary.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_user
  administrator_login_password = var.sql_admin_pass
}

# Secondary SQL Server
resource "azurerm_mssql_server" "secondary" {
  name                         = "sql-secondary-${var.project}-001"
  resource_group_name          = azurerm_resource_group.secondary.name
  location                     = azurerm_resource_group.secondary.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_user
  administrator_login_password = var.sql_admin_pass
}

# Database on primary
resource "azurerm_mssql_database" "main" {
  name      = "appdb"
  server_id = azurerm_mssql_server.primary.id
  sku_name  = "S1"
}

# Failover group
resource "azurerm_mssql_failover_group" "main" {
  name      = "fg-${var.project}"
  server_id = azurerm_mssql_server.primary.id
  databases = [azurerm_mssql_database.main.id]

  partner_server {
    id = azurerm_mssql_server.secondary.id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 1
  }
}

# GRS Storage
resource "azurerm_storage_account" "grs" {
  name                     = "st${var.project}dr001"
  resource_group_name      = azurerm_resource_group.primary.name
  location                 = azurerm_resource_group.primary.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

output "failover_group_endpoint" {
  value = "${azurerm_mssql_failover_group.main.name}.database.windows.net"
}
output "primary_server"   { value = azurerm_mssql_server.primary.fully_qualified_domain_name }
output "secondary_server" { value = azurerm_mssql_server.secondary.fully_qualified_domain_name }

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

# ── Random suffix to ensure globally unique names ──────────────────────────────
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ── Resource Group ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-redis-proj57-${random_string.suffix.result}"
  location = var.location

  tags = {
    project     = "5.7-redis-cache"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ── Azure Cache for Redis — C1 Standard (1 GB, with replication + SLA) ─────────
resource "azurerm_redis_cache" "main" {
  name                = "redis-proj57-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # C1 Standard: 1 GB, replication, persistence, SLA 99.9%
  capacity = 1
  family   = "C"
  sku_name = "Standard"

  # Security: disable non-TLS port
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  # Eviction policy — appropriate for a pure cache workload
  redis_configuration {
    maxmemory_policy = "allkeys-lru"

    # Enable RDB persistence (snapshot every 60 minutes)
    rdb_backup_enabled            = true
    rdb_backup_frequency          = 60
    rdb_backup_max_snapshot_count = 1
    rdb_storage_connection_string = azurerm_storage_account.redis_backup.primary_blob_connection_string
  }

  # Patch window — Tuesday 02:00 UTC to minimise disruption
  patch_schedule {
    day_of_week    = "Tuesday"
    start_hour_utc = 2
  }

  tags = azurerm_resource_group.main.tags
}

# ── Storage Account for Redis RDB backups ──────────────────────────────────────
resource "azurerm_storage_account" "redis_backup" {
  name                     = "stredisbkp${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = azurerm_resource_group.main.tags
}

# ── Azure SQL Server (simulated backend data store) ────────────────────────────
resource "azurerm_mssql_server" "main" {
  name                         = "sql-proj57-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_mssql_database" "main" {
  name      = "appdb"
  server_id = azurerm_mssql_server.main.id
  sku_name  = "Basic"  # 5 DTU, 2 GB — sufficient for demo

  tags = azurerm_resource_group.main.tags
}

# Allow Azure services to reach SQL (for App Service / Functions)
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ── Variables ──────────────────────────────────────────────────────────────────
variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "dev"
}

variable "sql_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
}

# ── Outputs ────────────────────────────────────────────────────────────────────
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "redis_name" {
  description = "Name of the Redis cache instance"
  value       = azurerm_redis_cache.main.name
}

output "redis_hostname" {
  description = "Redis cache hostname (use with port 6380 + SSL)"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_port" {
  description = "Redis SSL port"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_primary_key" {
  description = "Redis primary access key"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_connection_string" {
  description = "ADO.NET connection string for the SQL database"
  value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.main.name};User ID=${var.sql_admin_username};Password=${var.sql_admin_password};Encrypt=True;"
  sensitive   = true
}

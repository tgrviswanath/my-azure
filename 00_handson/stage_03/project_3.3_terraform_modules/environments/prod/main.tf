terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "prod" {
  name     = "rg-prod-modules"
  location = "East US"
}

module "vnet" {
  source              = "../../modules/vnet"
  name                = "vnet-prod"
  resource_group_name = azurerm_resource_group.prod.name
  location            = azurerm_resource_group.prod.location
  address_space       = ["10.1.0.0/16"]
  subnets             = { "subnet-web" = "10.1.1.0/24", "subnet-app" = "10.1.2.0/24", "subnet-db" = "10.1.3.0/24" }
  tags                = { environment = "prod" }
}

module "sql" {
  source              = "../../modules/sql"
  name                = "sql-prod-modules-001"
  resource_group_name = azurerm_resource_group.prod.name
  location            = azurerm_resource_group.prod.location
  admin_password      = var.sql_password
  sku_name            = "S1"
}

variable "sql_password" { type = string; sensitive = true }

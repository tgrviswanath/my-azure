terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "dev" {
  name     = "rg-dev-modules"
  location = "East US"
}

module "vnet" {
  source              = "../../modules/vnet"
  name                = "vnet-dev"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  address_space       = ["10.0.0.0/16"]
  subnets             = { "subnet-web" = "10.0.1.0/24", "subnet-db" = "10.0.2.0/24" }
  tags                = { environment = "dev" }
}

module "sql" {
  source              = "../../modules/sql"
  name                = "sql-dev-modules-001"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  admin_password      = var.sql_password
  sku_name            = "Basic"
}

variable "sql_password" { type = string; sensitive = true }

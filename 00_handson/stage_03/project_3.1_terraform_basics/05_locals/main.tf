terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" { features {} }

variable "project" { default = "handson" }
variable "environment" { default = "dev" }

locals {
  prefix   = "${var.project}-${var.environment}"
  location = "East US"
  common_tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}"
  location = local.location
  tags     = local.common_tags
}

resource "azurerm_storage_account" "main" {
  name                     = "st${replace(local.prefix, "-", "")}001"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.common_tags
}

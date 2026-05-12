terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {}
}

# ─────────────────────────────────────────────
# Root Variables
# ─────────────────────────────────────────────

variable "environment" {
  type        = string
  description = "Environment name: dev, qa, or prod"
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "Environment must be dev, qa, or prod."
  }
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "vm_count" {
  type    = number
  default = 1
}

variable "sql_sku" {
  type    = string
  default = "Basic"
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

variable "appgw_capacity" {
  type    = number
  default = 1
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = "rg-modules-${var.environment}"
  location = var.location
  tags = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "terraform-modules"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ─────────────────────────────────────────────
# Module: VNet
# ─────────────────────────────────────────────

module "vnet" {
  source = "./modules/vnet"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  vnet_address_space  = "10.0.0.0/16"
  tags                = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Module: VM
# ─────────────────────────────────────────────

module "vm" {
  source = "./modules/vm"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  subnet_id           = module.vnet.web_subnet_id
  vm_size             = var.vm_size
  vm_count            = var.vm_count
  admin_username      = "azureuser"
  tags                = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Module: SQL
# ─────────────────────────────────────────────

module "sql" {
  source = "./modules/sql"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  suffix              = random_string.suffix.result
  sku_name            = var.sql_sku
  admin_username      = "sqladmin"
  admin_password      = var.sql_admin_password
  allowed_subnet_id   = module.vnet.web_subnet_id
  tags                = azurerm_resource_group.main.tags
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "environment" {
  value = var.environment
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "vnet_id" {
  value = module.vnet.vnet_id
}

output "vm_public_ips" {
  value = module.vm.public_ips
}

output "sql_server_fqdn" {
  value = module.sql.server_fqdn
}

# ─────────────────────────────────────────────
# modules/vnet/main.tf
# ─────────────────────────────────────────────
# NOTE: In a real project, each module would be in its own directory.
# For this learning project, the module code is shown below as comments.
# Create the files at terraform/modules/vnet/main.tf etc.

# modules/vnet/variables.tf:
# variable "resource_group_name" { type = string }
# variable "location" { type = string }
# variable "environment" { type = string }
# variable "vnet_address_space" { type = string, default = "10.0.0.0/16" }
# variable "tags" { type = map(string), default = {} }

# modules/vnet/main.tf:
# resource "azurerm_virtual_network" "main" {
#   name                = "vnet-${var.environment}"
#   resource_group_name = var.resource_group_name
#   location            = var.location
#   address_space       = [var.vnet_address_space]
#   tags                = var.tags
# }
# resource "azurerm_subnet" "web" { ... address_prefixes = ["10.0.1.0/24"] }
# resource "azurerm_subnet" "db"  { ... address_prefixes = ["10.0.3.0/24"] }

# modules/vnet/outputs.tf:
# output "vnet_id" { value = azurerm_virtual_network.main.id }
# output "web_subnet_id" { value = azurerm_subnet.web.id }
# output "db_subnet_id" { value = azurerm_subnet.db.id }

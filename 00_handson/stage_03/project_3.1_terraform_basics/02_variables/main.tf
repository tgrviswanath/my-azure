terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" { features {} }

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.environment}-demo"
  location = var.location
  tags     = merge(var.tags, { environment = var.environment })
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

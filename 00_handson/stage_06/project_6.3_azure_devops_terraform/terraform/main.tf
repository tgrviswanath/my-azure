# Project 6.3 — Azure DevOps + Terraform Pipeline
# State backend using Azure Storage

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstateado001"
    container_name       = "tfstate"
    key                  = "stage-06/project-6.3/terraform.tfstate"
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}-ado-demo"
  location = var.location
  tags     = { Project = var.project, ManagedBy = "terraform", Pipeline = "azure-devops" }
}

resource "azurerm_storage_account" "demo" {
  name                     = "st${var.project}ado001"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = { Project = var.project }
}

output "resource_group" { value = azurerm_resource_group.main.name }
output "storage_account" { value = azurerm_storage_account.demo.name }

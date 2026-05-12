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

variable "resource_group_name" { default = "rg-data-quality-lab" }
variable "location"            { default = "East US" }

resource "azurerm_resource_group" "dq" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "data-quality", stage = "09", env = "lab" }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Storage Account for Data Docs and data
resource "azurerm_storage_account" "dq" {
  name                     = "stdq${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.dq.name
  location                 = azurerm_resource_group.dq.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true

  # Enable static website for Data Docs hosting
  static_website {
    index_document = "index.html"
  }

  tags = azurerm_resource_group.dq.tags
}

resource "azurerm_storage_container" "processed" {
  name                  = "processed"
  storage_account_name  = azurerm_storage_account.dq.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "data_docs" {
  name                  = "data-docs"
  storage_account_name  = azurerm_storage_account.dq.name
  container_access_type = "blob"  # Public read for Data Docs
}

# Azure Function App for validation trigger
resource "azurerm_service_plan" "dq" {
  name                = "asp-dq-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dq.name
  location            = azurerm_resource_group.dq.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan (pay per execution)

  tags = azurerm_resource_group.dq.tags
}

resource "azurerm_storage_account" "function" {
  name                     = "stfunc${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.dq.name
  location                 = azurerm_resource_group.dq.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = azurerm_resource_group.dq.tags
}

resource "azurerm_linux_function_app" "dq" {
  name                = "func-dq-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dq.name
  location            = azurerm_resource_group.dq.location

  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  service_plan_id            = azurerm_service_plan.dq.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "AzureWebJobsFeatureFlags"    = "EnableWorkerIndexing"
    "DATA_STORAGE_ACCOUNT"        = azurerm_storage_account.dq.name
    "DATA_STORAGE_KEY"            = azurerm_storage_account.dq.primary_access_key
    "DOCS_CONTAINER"              = azurerm_storage_container.data_docs.name
  }

  tags = azurerm_resource_group.dq.tags
}

# Grant Function App access to data storage
resource "azurerm_role_assignment" "func_storage" {
  scope                = azurerm_storage_account.dq.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.dq.identity[0].principal_id
}

# Outputs
output "function_app_name" {
  value = azurerm_linux_function_app.dq.name
}

output "function_app_url" {
  value = "https://${azurerm_linux_function_app.dq.default_hostname}"
}

output "storage_account_name" {
  value = azurerm_storage_account.dq.name
}

output "data_docs_url" {
  description = "Static website URL for Data Docs"
  value       = azurerm_storage_account.dq.primary_web_endpoint
}

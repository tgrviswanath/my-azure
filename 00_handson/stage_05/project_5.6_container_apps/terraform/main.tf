terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "ca" {
  name     = "rg-container-apps"
  location = "East US"
}

resource "azurerm_log_analytics_workspace" "ca" {
  name                = "log-container-apps"
  location            = azurerm_resource_group.ca.location
  resource_group_name = azurerm_resource_group.ca.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "ca" {
  name                       = "cae-handson"
  location                   = azurerm_resource_group.ca.location
  resource_group_name        = azurerm_resource_group.ca.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.ca.id
}

resource "azurerm_container_app" "myapp" {
  name                         = "ca-myapp"
  container_app_environment_id = azurerm_container_app_environment.ca.id
  resource_group_name          = azurerm_resource_group.ca.name
  revision_mode                = "Single"

  template {
    container {
      name   = "myapp"
      image  = "acrhandson001.azurecr.io/myapp:v1.0"
      cpu    = 0.25
      memory = "0.5Gi"
    }

    min_replicas = 0
    max_replicas = 10
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

output "app_url" {
  value = "https://${azurerm_container_app.myapp.ingress[0].fqdn}"
}

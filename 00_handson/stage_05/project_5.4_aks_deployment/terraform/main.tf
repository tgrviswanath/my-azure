terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

resource "azurerm_resource_group" "aks" {
  name     = "rg-aks"
  location = "East US"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-handson"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "aks-handson"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    load_balancer_sku = "standard"
  }
}

# Grant AKS pull access to ACR
data "azurerm_container_registry" "acr" {
  name                = "acrhandson001"
  resource_group_name = "rg-acr"
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = data.azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

output "kube_config_command" {
  value = "az aks get-credentials --resource-group rg-aks --name aks-handson"
}

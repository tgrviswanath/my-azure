# Project 6.5 — Kubernetes GitOps with ArgoCD
# Creates AKS cluster + ACR for GitOps demo

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "gitops" {
  name     = "rg-gitops"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-06" }
}

resource "azurerm_container_registry" "acr" {
  name                = "acrgitops${var.project}001"
  resource_group_name = azurerm_resource_group.gitops.name
  location            = azurerm_resource_group.gitops.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-gitops"
  location            = azurerm_resource_group.gitops.location
  resource_group_name = azurerm_resource_group.gitops.name
  dns_prefix          = "aks-gitops"

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = "Standard_D2s_v3"
  }

  identity { type = "SystemAssigned" }

  tags = { Project = var.project }
}

# Allow AKS to pull from ACR
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

output "aks_name"       { value = azurerm_kubernetes_cluster.aks.name }
output "acr_login_server" { value = azurerm_container_registry.acr.login_server }
output "get_credentials" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.gitops.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

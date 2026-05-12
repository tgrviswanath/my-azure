# Project 10.4 — Kubernetes on AKS (Production-grade)

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

resource "azurerm_resource_group" "aks" {
  name     = "rg-aks-prod"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-10" }
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${var.project}prod001"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  sku                 = "Basic"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project}"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "aks-${var.project}"
  kubernetes_version  = "1.28"

  # System node pool
  default_node_pool {
    name                = "system"
    node_count          = 1
    vm_size             = "Standard_D2s_v3"
    only_critical_addons_enabled = true  # Reserve for system pods
  }

  identity { type = "SystemAssigned" }

  # Enable OIDC issuer for workload identity
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Azure Monitor integration
  monitor_metrics {}

  tags = { Project = var.project }
}

# User node pool for application workloads
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D2s_v3"
  node_count            = 2
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 5
  tags                  = { Project = var.project }
}

# Allow AKS to pull from ACR
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

output "aks_name"         { value = azurerm_kubernetes_cluster.main.name }
output "acr_login_server" { value = azurerm_container_registry.acr.login_server }
output "get_credentials"  {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

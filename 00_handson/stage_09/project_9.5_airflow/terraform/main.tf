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

variable "resource_group_name" { default = "rg-airflow-lab" }
variable "location"            { default = "East US" }
variable "aks_name"            { default = "aks-airflow" }
variable "node_count"          { default = 2 }
variable "node_vm_size"        { default = "Standard_D2s_v3" }

resource "azurerm_resource_group" "airflow" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "airflow-orchestration", stage = "09", env = "lab" }
}

# AKS Cluster for Airflow
resource "azurerm_kubernetes_cluster" "airflow" {
  name                = var.aks_name
  location            = azurerm_resource_group.airflow.location
  resource_group_name = azurerm_resource_group.airflow.name
  dns_prefix          = "airflow-lab"
  kubernetes_version  = "1.28"

  # System node pool (for Airflow control plane components)
  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    os_disk_size_gb     = 50
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 4

    node_labels = {
      "role" = "system"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  # Enable monitoring
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.airflow.id
  }

  tags = azurerm_resource_group.airflow.tags
}

# Log Analytics for AKS monitoring
resource "azurerm_log_analytics_workspace" "airflow" {
  name                = "law-airflow-lab"
  location            = azurerm_resource_group.airflow.location
  resource_group_name = azurerm_resource_group.airflow.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = azurerm_resource_group.airflow.tags
}

# Azure Container Registry (for custom Airflow image)
resource "azurerm_container_registry" "airflow" {
  name                = "acr${replace(var.aks_name, "-", "")}lab"
  resource_group_name = azurerm_resource_group.airflow.name
  location            = azurerm_resource_group.airflow.location
  sku                 = "Basic"
  admin_enabled       = false

  tags = azurerm_resource_group.airflow.tags
}

# Grant AKS pull access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.airflow.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.airflow.id
  skip_service_principal_aad_check = true
}

# Outputs
output "aks_name" {
  value = azurerm_kubernetes_cluster.airflow.name
}

output "aks_resource_group" {
  value = azurerm_resource_group.airflow.name
}

output "acr_login_server" {
  value = azurerm_container_registry.airflow.login_server
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.airflow.name} --name ${azurerm_kubernetes_cluster.airflow.name}"
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.airflow.id
}

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ── Resource Group ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-aks-cicd-proj61-${random_string.suffix.result}"
  location = var.location

  tags = {
    project     = "6.1-github-actions-aks"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ── Azure Container Registry ───────────────────────────────────────────────────
resource "azurerm_container_registry" "main" {
  name                = "acrproj61${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false  # Use managed identity / SP, not admin credentials

  tags = azurerm_resource_group.main.tags
}

# ── AKS Cluster ────────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-proj61-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aksproj61${random_string.suffix.result}"
  kubernetes_version  = var.kubernetes_version

  # System node pool
  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    os_disk_size_gb     = 30
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = false

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
    }
  }

  # Use system-assigned managed identity for the control plane
  identity {
    type = "SystemAssigned"
  }

  # Network configuration
  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }

  # RBAC
  role_based_access_control_enabled = true

  tags = azurerm_resource_group.main.tags
}

# ── Grant AKS kubelet identity AcrPull on ACR ──────────────────────────────────
# This allows AKS nodes to pull images from ACR without Kubernetes image pull secrets
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

# ── Variables ──────────────────────────────────────────────────────────────────
variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

# ── Outputs ────────────────────────────────────────────────────────────────────
output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "acr_name" {
  description = "ACR registry name"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "ACR login server URL"
  value       = azurerm_container_registry.main.login_server
}

output "acr_id" {
  description = "ACR resource ID"
  value       = azurerm_container_registry.main.id
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_id" {
  description = "AKS cluster resource ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_kube_config" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

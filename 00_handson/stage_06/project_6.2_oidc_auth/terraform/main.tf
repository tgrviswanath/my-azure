# Project 6.2 — Secure OIDC GitHub Authentication
# Creates App Registration + Federated Credential + RBAC assignment

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
    azuread = { source = "hashicorp/azuread" version = "~> 2.0" }
  }
}

provider "azurerm" { features {} }
provider "azuread" {}

variable "github_repo"  { description = "GitHub repo in org/repo format" }
variable "github_branch" { default = "main" }
variable "role"          { default = "Contributor" }

data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

# App Registration
resource "azuread_application" "github_actions" {
  display_name = "github-actions-oidc-${replace(var.github_repo, "/", "-")}"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# Federated credential — main branch
resource "azuread_application_federated_identity_credential" "main_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-${replace(var.github_branch, "/", "-")}"
  description    = "GitHub Actions OIDC for ${var.github_repo} branch ${var.github_branch}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
}

# Federated credential — pull requests
resource "azuread_application_federated_identity_credential" "pull_requests" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-pull-requests"
  description    = "GitHub Actions OIDC for ${var.github_repo} pull requests"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
}

# RBAC role assignment
resource "azurerm_role_assignment" "github_actions" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = var.role
  principal_id         = azuread_service_principal.github_actions.object_id
}

output "client_id"       { value = azuread_application.github_actions.client_id }
output "tenant_id"       { value = data.azuread_client_config.current.tenant_id }
output "subscription_id" { value = data.azurerm_subscription.current.subscription_id }

output "github_secrets" {
  value = <<-EOT
    Add these to GitHub → Settings → Secrets → Actions:
    AZURE_CLIENT_ID       = ${azuread_application.github_actions.client_id}
    AZURE_TENANT_ID       = ${data.azuread_client_config.current.tenant_id}
    AZURE_SUBSCRIPTION_ID = ${data.azurerm_subscription.current.subscription_id}
  EOT
}

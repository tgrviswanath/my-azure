# Project 6.4 — Multi-subscription CI/CD Pipeline
# Creates App Registrations + federated credentials for dev/qa/prod

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
    azuread = { source = "hashicorp/azuread" version = "~> 2.0" }
  }
}

provider "azurerm" { features {} }
provider "azuread" {}

variable "github_repo" { description = "GitHub repo (org/repo)" }
variable "environments" {
  default = ["dev", "qa", "prod"]
}

data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

# Create one App Registration per environment
resource "azuread_application" "env" {
  for_each     = toset(var.environments)
  display_name = "github-actions-${each.key}"
}

resource "azuread_service_principal" "env" {
  for_each  = azuread_application.env
  client_id = each.value.client_id
}

# Federated credential per environment (scoped to GitHub Environment)
resource "azuread_application_federated_identity_credential" "env" {
  for_each       = azuread_application.env
  application_id = each.value.id
  display_name   = "github-env-${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:environment:${each.key}"
}

# RBAC assignment per environment SP
resource "azurerm_role_assignment" "env" {
  for_each             = azuread_service_principal.env
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = each.value.object_id
}

output "environment_credentials" {
  value = {
    for env, app in azuread_application.env : env => {
      client_id       = app.client_id
      tenant_id       = data.azuread_client_config.current.tenant_id
      subscription_id = data.azurerm_subscription.current.subscription_id
    }
  }
}

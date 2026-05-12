# Project 8.3 — Azure Policy Compliance Automation

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

variable "location" { default = "East US" }
variable "project"  { default = "handson" }

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "policy" {
  name     = "rg-policy-demo"
  location = var.location
  tags     = { Project = var.project, Stage = "stage-08" }
}

# Custom policy: require tags on resource groups
resource "azurerm_policy_definition" "require_tags" {
  name         = "require-project-tag"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require Project tag on resource groups"
  description  = "Enforces that all resource groups have a Project tag"

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type"; equals = "Microsoft.Resources/subscriptions/resourceGroups" },
        { field = "tags['Project']"; exists = "false" }
      ]
    }
    then = { effect = "Audit" }
  })
}

# Assign built-in policy: allowed locations
resource "azurerm_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  scope                = data.azurerm_subscription.current.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  display_name         = "Allowed locations"
  description          = "Restrict resource creation to East US and West US"

  parameters = jsonencode({
    listOfAllowedLocations = { value = ["eastus", "westus", "eastus2"] }
  })
}

# Assign custom tag policy
resource "azurerm_policy_assignment" "require_tags" {
  name                 = "require-project-tag"
  scope                = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.require_tags.id
  display_name         = "Require Project tag"
}

output "policy_assignment_id" { value = azurerm_policy_assignment.require_tags.id }

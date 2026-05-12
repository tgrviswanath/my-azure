# Project 10.1 — Multi-subscription Azure Landing Zone

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" version = "~> 3.0" }
    azuread = { source = "hashicorp/azuread" version = "~> 2.0" }
  }
}

provider "azurerm" { features {} }
provider "azuread" {}

data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

# Management Group hierarchy
resource "azurerm_management_group" "platform" {
  display_name = "Platform"
}

resource "azurerm_management_group" "landing_zones" {
  display_name = "Landing Zones"
}

resource "azurerm_management_group" "corp" {
  display_name               = "Corp"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

resource "azurerm_management_group" "online" {
  display_name               = "Online"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

# Move current subscription into Corp MG
resource "azurerm_management_group_subscription_association" "corp_dev" {
  management_group_id = azurerm_management_group.corp.id
  subscription_id     = data.azurerm_subscription.current.id
}

# Policy: require Project tag at Landing Zones MG
resource "azurerm_management_group_policy_assignment" "require_tags" {
  name                 = "require-project-tag"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  management_group_id  = azurerm_management_group.landing_zones.id
  display_name         = "Require a tag on resource groups"
  parameters = jsonencode({ tagName = { value = "Project" } })
}

output "platform_mg_id"      { value = azurerm_management_group.platform.id }
output "landing_zones_mg_id" { value = azurerm_management_group.landing_zones.id }
output "corp_mg_id"          { value = azurerm_management_group.corp.id }

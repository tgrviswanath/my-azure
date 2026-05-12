terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm"; version = "~> 3.0" }
  }
}

provider "azurerm" { features {} }

# Read outputs from the main state
data "terraform_remote_state" "main" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate001"
    container_name       = "tfstate"
    key                  = "main.tfstate"
  }
}

# Use the VNet ID from main state
resource "azurerm_subnet" "consumer" {
  name                 = "subnet-consumer"
  resource_group_name  = data.terraform_remote_state.main.outputs.resource_group_name
  virtual_network_name = "vnet-remote-state-demo"
  address_prefixes     = ["10.0.10.0/24"]
}

output "consumed_vnet_id" {
  value = data.terraform_remote_state.main.outputs.vnet_id
}

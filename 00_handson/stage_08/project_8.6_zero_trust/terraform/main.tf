terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Variables
variable "resource_group_name" { default = "rg-zero-trust-lab" }
variable "location"            { default = "East US" }
variable "vnet_address_space"  { default = "10.0.0.0/16" }

data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "zt" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    project = "zero-trust"
    stage   = "08"
    env     = "lab"
  }
}

# ── Virtual Network ───────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "zt" {
  name                = "vnet-zero-trust"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.zt.location
  resource_group_name = azurerm_resource_group.zt.name
  tags                = azurerm_resource_group.zt.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.zt.name
  virtual_network_name = azurerm_virtual_network.zt.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.zt.name
  virtual_network_name = azurerm_virtual_network.zt.name
  address_prefixes     = ["10.0.2.0/24"]

  # Required for private endpoints
  private_endpoint_network_policies_enabled = false
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"  # Must be this exact name
  resource_group_name  = azurerm_resource_group.zt.name
  virtual_network_name = azurerm_virtual_network.zt.name
  address_prefixes     = ["10.0.3.0/24"]
}

# ── Network Security Groups ───────────────────────────────────────────────────

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  location            = azurerm_resource_group.zt.location
  resource_group_name = azurerm_resource_group.zt.name

  # Allow HTTPS inbound from Application Gateway only
  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.0.4.0/24"  # App Gateway subnet
    destination_address_prefix = "*"
  }

  # Deny all other inbound (no 0.0.0.0/0 on 22 or 3389)
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = azurerm_resource_group.zt.tags
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# ── Key Vault (with Private Endpoint) ────────────────────────────────────────

resource "azurerm_key_vault" "zt" {
  name                        = "kv-zerotrust-${random_string.suffix.result}"
  location                    = azurerm_resource_group.zt.location
  resource_group_name         = azurerm_resource_group.zt.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  # Disable public network access — only accessible via Private Endpoint
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    # No IP rules — only private endpoint access
  }

  tags = azurerm_resource_group.zt.tags
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-keyvault-lab"
  location            = azurerm_resource_group.zt.location
  resource_group_name = azurerm_resource_group.zt.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.zt.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-keyvault"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }

  tags = azurerm_resource_group.zt.tags
}

# Private DNS Zone for Key Vault
resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.zt.name
  tags                = azurerm_resource_group.zt.tags
}

# Link DNS Zone to VNet (so VMs in VNet can resolve private IPs)
resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "pdns-link-keyvault"
  resource_group_name   = azurerm_resource_group.zt.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.zt.id
  registration_enabled  = false
  tags                  = azurerm_resource_group.zt.tags
}

# ── Storage Account (with Private Endpoint) ───────────────────────────────────

resource "azurerm_storage_account" "zt" {
  name                     = "stzerotrust${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.zt.name
  location                 = azurerm_resource_group.zt.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Zero Trust: disable public access
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    # No IP rules — only private endpoint
  }

  tags = azurerm_resource_group.zt.tags
}

# Private Endpoint for Storage (Blob)
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-storage-blob"
  location            = azurerm_resource_group.zt.location
  resource_group_name = azurerm_resource_group.zt.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-storage-blob"
    private_connection_resource_id = azurerm_storage_account.zt.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-storage-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = azurerm_resource_group.zt.tags
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.zt.name
  tags                = azurerm_resource_group.zt.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "pdns-link-storage-blob"
  resource_group_name   = azurerm_resource_group.zt.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.zt.id
  registration_enabled  = false
  tags                  = azurerm_resource_group.zt.tags
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "key_vault_name" {
  value = azurerm_key_vault.zt.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.zt.vault_uri
}

output "storage_account_name" {
  value = azurerm_storage_account.zt.name
}

output "private_endpoint_key_vault_ip" {
  description = "Private IP of Key Vault PE (verify DNS resolves to this)"
  value       = azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address
}

output "private_endpoint_storage_ip" {
  description = "Private IP of Storage PE"
  value       = azurerm_private_endpoint.storage_blob.private_service_connection[0].private_ip_address
}

output "vnet_id" {
  value = azurerm_virtual_network.zt.id
}

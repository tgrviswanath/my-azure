# Project 0.1 — Local Azure Development Setup
# Terraform configured to use Azurite (local Azure Storage emulator)

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# For local development, we use the azurite provider workaround
# In real Azure, replace with proper azurerm provider config
provider "azurerm" {
  features {}
  # For local testing with Azurite, skip provider registration
  skip_provider_registration = true
}

# NOTE: Azurite does not support full azurerm provider
# Use Azure CLI with --connection-string for local testing:
# az storage container create --connection-string "UseDevelopmentStorage=true" --name demo

# These outputs document the local endpoints for reference
output "local_blob_endpoint" {
  value       = "http://localhost:10000/devstoreaccount1"
  description = "Azurite Blob Storage endpoint"
}

output "local_queue_endpoint" {
  value       = "http://localhost:10001/devstoreaccount1"
  description = "Azurite Queue Storage endpoint"
}

output "local_table_endpoint" {
  value       = "http://localhost:10002/devstoreaccount1"
  description = "Azurite Table Storage endpoint"
}

output "functions_endpoint" {
  value       = "http://localhost:7071/api"
  description = "Azure Functions Core Tools local endpoint"
}

output "connection_string" {
  value = join(";", [
    "DefaultEndpointsProtocol=http",
    "AccountName=devstoreaccount1",
    "AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==",
    "BlobEndpoint=http://localhost:10000/devstoreaccount1",
    "QueueEndpoint=http://localhost:10001/devstoreaccount1",
    "TableEndpoint=http://localhost:10002/devstoreaccount1"
  ])
  description = "Full Azurite connection string for SDK use"
  sensitive   = false
}

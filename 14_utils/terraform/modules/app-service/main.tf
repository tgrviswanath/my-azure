# ============================================================
# Terraform Module: App Service
# Reusable module for App Service + Plan + Managed Identity
# ============================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────
variable "name"                { type = string; description = "App name" }
variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "plan_sku"            { type = string; default = "B1" }
variable "runtime_stack"       { type = string; default = "NODE|18-lts" }
variable "always_on"           { type = bool;   default = true }
variable "https_only"          { type = bool;   default = true }
variable "health_check_path"   { type = string; default = "/health" }
variable "app_settings"        { type = map(string); default = {} }
variable "vnet_subnet_id"      { type = string; default = null }
variable "tags"                { type = map(string); default = {} }

variable "slots" {
  type    = list(string)
  default = ["staging"]
  description = "Deployment slot names"
}

variable "autoscale" {
  type = object({
    enabled   = bool
    min_count = number
    max_count = number
    cpu_threshold = number
  })
  default = {
    enabled       = false
    min_count     = 1
    max_count     = 5
    cpu_threshold = 70
  }
}

# ── App Service Plan ──────────────────────────────────────────────────────────
resource "azurerm_service_plan" "this" {
  name                = "asp-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.plan_sku
  tags                = var.tags
}

# ── Web App ───────────────────────────────────────────────────────────────────
resource "azurerm_linux_web_app" "this" {
  name                      = var.name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  service_plan_id           = azurerm_service_plan.this.id
  https_only                = var.https_only
  virtual_network_subnet_id = var.vnet_subnet_id
  tags                      = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on         = var.always_on
    http2_enabled     = true
    minimum_tls_version = "1.2"
    ftps_state        = "Disabled"
    health_check_path = var.health_check_path

    application_stack {
      node_version = can(regex("^NODE\\|", var.runtime_stack)) ? replace(var.runtime_stack, "NODE|", "") : null
      python_version = can(regex("^PYTHON\\|", var.runtime_stack)) ? replace(var.runtime_stack, "PYTHON|", "") : null
      dotnet_version = can(regex("^DOTNET\\|", var.runtime_stack)) ? replace(var.runtime_stack, "DOTNET|", "") : null
    }
  }

  app_settings = var.app_settings

  logs {
    application_logs {
      file_system_level = "Warning"
    }
    http_logs {
      retention_in_days = 7
    }
  }
}

# ── Deployment Slots ──────────────────────────────────────────────────────────
resource "azurerm_linux_web_app_slot" "slots" {
  for_each       = toset(var.slots)
  name           = each.value
  app_service_id = azurerm_linux_web_app.this.id
  tags           = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on         = true
    http2_enabled     = true
    minimum_tls_version = "1.2"
    ftps_state        = "Disabled"
    health_check_path = var.health_check_path

    application_stack {
      node_version = can(regex("^NODE\\|", var.runtime_stack)) ? replace(var.runtime_stack, "NODE|", "") : null
    }
  }

  app_settings = merge(var.app_settings, {
    "SLOT_NAME" = each.value
  })
}

# ── Autoscale ─────────────────────────────────────────────────────────────────
resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.autoscale.enabled ? 1 : 0
  name                = "autoscale-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = var.tags

  profile {
    name = "default"

    capacity {
      default = var.autoscale.min_count
      minimum = var.autoscale.min_count
      maximum = var.autoscale.max_count
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale.cpu_threshold
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "id"                   { value = azurerm_linux_web_app.this.id }
output "name"                 { value = azurerm_linux_web_app.this.name }
output "default_hostname"     { value = azurerm_linux_web_app.this.default_hostname }
output "url"                  { value = "https://${azurerm_linux_web_app.this.default_hostname}" }
output "principal_id"         { value = azurerm_linux_web_app.this.identity[0].principal_id }
output "plan_id"              { value = azurerm_service_plan.this.id }
output "slot_principal_ids"   {
  value = { for k, v in azurerm_linux_web_app_slot.slots : k => v.identity[0].principal_id }
}

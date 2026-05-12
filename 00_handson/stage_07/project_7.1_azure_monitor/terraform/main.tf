terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ─── Variables ────────────────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-monitor-demo"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@example.com"
}

variable "vm_admin_username" {
  description = "Admin username for the demo VM"
  type        = string
  default     = "azureuser"
}

# ─── Resource Group ───────────────────────────────────────────────────────────

resource "azurerm_resource_group" "monitor" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "7.1-azure-monitor"
    environment = "demo"
    managed_by  = "terraform"
  }
}

# ─── Log Analytics Workspace ──────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-monitor-demo"
  location            = azurerm_resource_group.monitor.location
  resource_group_name = azurerm_resource_group.monitor.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    project = "7.1-azure-monitor"
  }
}

# ─── Virtual Network (for demo VM) ───────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-monitor-demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.monitor.location
  resource_group_name = azurerm_resource_group.monitor.name
}

resource "azurerm_subnet" "main" {
  name                 = "snet-monitor-demo"
  resource_group_name  = azurerm_resource_group.monitor.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "vm" {
  name                = "pip-vm-monitor-demo"
  location            = azurerm_resource_group.monitor.location
  resource_group_name = azurerm_resource_group.monitor.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-vm-monitor-demo"
  location            = azurerm_resource_group.monitor.location
  resource_group_name = azurerm_resource_group.monitor.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

# ─── Demo VM ──────────────────────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "demo" {
  name                = "vm-monitor-demo"
  resource_group_name = azurerm_resource_group.monitor.name
  location            = azurerm_resource_group.monitor.location
  size                = "Standard_B2s"
  admin_username      = var.vm_admin_username

  network_interface_ids = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    project = "7.1-azure-monitor"
  }
}

# ─── Azure Monitor Agent Extension ───────────────────────────────────────────

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.demo.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  tags = {
    project = "7.1-azure-monitor"
  }
}

# ─── Diagnostic Settings (VM → Log Analytics) ────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "vm" {
  name                       = "diag-vm-monitor-demo"
  target_resource_id         = azurerm_linux_virtual_machine.demo.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# ─── Action Group ─────────────────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-monitor-demo"
  resource_group_name = azurerm_resource_group.monitor.name
  short_name          = "agmonitor"

  email_receiver {
    name                    = "admin-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  webhook_receiver {
    name                    = "teams-webhook"
    service_uri             = "https://outlook.office.com/webhook/placeholder"
    use_common_alert_schema = true
  }

  tags = {
    project = "7.1-azure-monitor"
  }
}

# ─── CPU Alert Rule ───────────────────────────────────────────────────────────

resource "azurerm_monitor_metric_alert" "cpu_high" {
  name                = "alert-cpu-high"
  resource_group_name = azurerm_resource_group.monitor.name
  scopes              = [azurerm_linux_virtual_machine.demo.id]
  description         = "Alert when VM CPU exceeds 80% for 5 minutes"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = {
    project = "7.1-azure-monitor"
  }
}

# ─── Disk Read Alert Rule ─────────────────────────────────────────────────────

resource "azurerm_monitor_metric_alert" "disk_high" {
  name                = "alert-disk-read-high"
  resource_group_name = azurerm_resource_group.monitor.name
  scopes              = [azurerm_linux_virtual_machine.demo.id]
  description         = "Alert when OS disk read bytes/sec exceeds 50MB/s"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "OS Disk Read Bytes/Sec"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 50000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = {
    project = "7.1-azure-monitor"
  }
}

# ─── Network In Alert Rule ────────────────────────────────────────────────────

resource "azurerm_monitor_metric_alert" "network_in_high" {
  name                = "alert-network-in-high"
  resource_group_name = azurerm_resource_group.monitor.name
  scopes              = [azurerm_linux_virtual_machine.demo.id]
  description         = "Alert when network inbound exceeds 100MB in 5 minutes"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Network In Total"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 100000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = {
    project = "7.1-azure-monitor"
  }
}

# ─── Dashboard ────────────────────────────────────────────────────────────────

resource "azurerm_dashboard" "monitor" {
  name                = "dashboard-monitor-demo"
  resource_group_name = azurerm_resource_group.monitor.name
  location            = azurerm_resource_group.monitor.location

  tags = {
    project = "7.1-azure-monitor"
    hidden-title = "Azure Monitor Demo Dashboard"
  }

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = { x = 0, y = 0, colSpan = 6, rowSpan = 4 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_linux_virtual_machine.demo.id
                          }
                          name            = "Percentage CPU"
                          aggregationType = 4
                          namespace       = "microsoft.compute/virtualmachines"
                          metricVisualization = {
                            displayName = "CPU Percentage"
                          }
                        }
                      ]
                      title     = "VM CPU Percentage"
                      titleKind = 1
                      visualization = {
                        chartType = 2
                      }
                    }
                  }
                }
              }
            }
          }
          "1" = {
            position = { x = 6, y = 0, colSpan = 6, rowSpan = 4 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_linux_virtual_machine.demo.id
                          }
                          name            = "Network In Total"
                          aggregationType = 1
                          namespace       = "microsoft.compute/virtualmachines"
                          metricVisualization = {
                            displayName = "Network In"
                          }
                        }
                      ]
                      title     = "VM Network In"
                      titleKind = 1
                      visualization = {
                        chartType = 2
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    metadata = {
      model = {
        timeRange = {
          value = {
            relative = {
              duration = 24
              timeUnit = 1
            }
          }
          type = "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  })
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.monitor.name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Log Analytics Workspace customer ID (used for agent config)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "vm_id" {
  description = "Demo VM resource ID"
  value       = azurerm_linux_virtual_machine.demo.id
}

output "vm_public_ip" {
  description = "Demo VM public IP address"
  value       = azurerm_public_ip.vm.ip_address
}

output "action_group_id" {
  description = "Action Group resource ID"
  value       = azurerm_monitor_action_group.main.id
}

output "cpu_alert_id" {
  description = "CPU alert rule resource ID"
  value       = azurerm_monitor_metric_alert.cpu_high.id
}

output "dashboard_id" {
  description = "Azure Dashboard resource ID"
  value       = azurerm_dashboard.monitor.id
}

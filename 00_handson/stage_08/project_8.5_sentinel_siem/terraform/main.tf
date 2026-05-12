terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "resource_group_name" {
  default = "rg-sentinel-lab"
}

variable "location" {
  default = "East US"
}

variable "workspace_name" {
  default = "law-sentinel-lab"
}

# Resource Group
resource "azurerm_resource_group" "sentinel" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "sentinel-siem"
    stage   = "08"
    env     = "lab"
  }
}

# Log Analytics Workspace (required for Sentinel)
resource "azurerm_log_analytics_workspace" "sentinel" {
  name                = var.workspace_name
  location            = azurerm_resource_group.sentinel.location
  resource_group_name = azurerm_resource_group.sentinel.name
  sku                 = "PerGB2018"
  retention_in_days   = 90

  tags = azurerm_resource_group.sentinel.tags
}

# Enable Microsoft Sentinel on the Log Analytics Workspace
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel" {
  workspace_id = azurerm_log_analytics_workspace.sentinel.id
}

# Sentinel Analytics Rule — Brute Force Detection
resource "azurerm_sentinel_alert_rule_scheduled" "brute_force" {
  name                       = "brute-force-detection"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  display_name               = "Brute Force Attack — Multiple Failed Logins"
  description                = "Detects more than 10 failed login attempts from the same IP within 5 minutes. Indicates a brute force or password spray attack."
  severity                   = "High"
  enabled                    = true

  # KQL query to detect brute force
  query = <<-KQL
    SigninLogs
    | where ResultType != "0"
    | summarize 
        FailedAttempts = count(),
        DistinctUsers = dcount(UserPrincipalName),
        FirstAttempt = min(TimeGenerated),
        LastAttempt = max(TimeGenerated)
      by IPAddress, bin(TimeGenerated, 5m)
    | where FailedAttempts > 10
    | extend AlertDetail = strcat("IP: ", IPAddress, " | Attempts: ", FailedAttempts, " | Users targeted: ", DistinctUsers)
    | project TimeGenerated, IPAddress, FailedAttempts, DistinctUsers, FirstAttempt, LastAttempt, AlertDetail
  KQL

  query_frequency = "PT5M"
  query_period    = "PT5M"

  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  suppression_duration = "PT1H"
  suppression_enabled  = false

  tactics    = ["CredentialAccess"]
  techniques = ["T1110"]

  # Entity mapping for investigation graph
  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "IPAddress"
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}

# Sentinel Analytics Rule — Impossible Travel
resource "azurerm_sentinel_alert_rule_scheduled" "impossible_travel" {
  name                       = "impossible-travel-detection"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  display_name               = "Impossible Travel — Login from Two Distant Locations"
  description                = "Detects when a user logs in from two geographically distant locations within 60 minutes."
  severity                   = "Medium"
  enabled                    = true

  query = <<-KQL
    SigninLogs
    | where ResultType == "0"
    | project TimeGenerated, UserPrincipalName, Location, IPAddress, AppDisplayName
    | sort by UserPrincipalName asc, TimeGenerated asc
    | extend PrevLocation = prev(Location, 1)
    | extend PrevTime = prev(TimeGenerated, 1)
    | extend PrevUser = prev(UserPrincipalName, 1)
    | where UserPrincipalName == PrevUser
    | extend TimeDiffMinutes = datetime_diff('minute', TimeGenerated, PrevTime)
    | where Location != PrevLocation and TimeDiffMinutes < 60 and TimeDiffMinutes > 0
    | project TimeGenerated, UserPrincipalName, CurrentLocation = Location, PreviousLocation = PrevLocation, TimeDiffMinutes, IPAddress
  KQL

  query_frequency = "PT1H"
  query_period    = "PT2H"

  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  tactics    = ["InitialAccess"]
  techniques = ["T1078"]

  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "Name"
      column_name = "UserPrincipalName"
    }
  }

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "IPAddress"
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}

# Sentinel Analytics Rule — Privileged Account Activity Outside Business Hours
resource "azurerm_sentinel_alert_rule_scheduled" "after_hours_admin" {
  name                       = "after-hours-admin-activity"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  display_name               = "Privileged Account Activity Outside Business Hours"
  description                = "Detects admin/privileged account logins outside 8am-6pm UTC Monday-Friday."
  severity                   = "Medium"
  enabled                    = true

  query = <<-KQL
    AuditLogs
    | where TimeGenerated > ago(1h)
    | where OperationName in ("Add member to role", "Reset user password", "Delete user")
    | extend Hour = hourofday(TimeGenerated)
    | extend DayOfWeek = dayofweek(TimeGenerated)
    | where Hour < 8 or Hour > 18 or DayOfWeek == 0 or DayOfWeek == 6
    | extend InitiatedBy = tostring(InitiatedBy.user.userPrincipalName)
    | project TimeGenerated, OperationName, InitiatedBy, Result, Hour, DayOfWeek
  KQL

  query_frequency = "PT1H"
  query_period    = "PT1H"

  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  tactics    = ["PrivilegeEscalation"]
  techniques = ["T1078.004"]

  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "Name"
      column_name = "InitiatedBy"
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}

# Logic App for automated incident response (Playbook)
resource "azurerm_logic_app_workflow" "sentinel_playbook" {
  name                = "playbook-block-ip-notify"
  location            = azurerm_resource_group.sentinel.location
  resource_group_name = azurerm_resource_group.sentinel.name

  tags = azurerm_resource_group.sentinel.tags
}

# Outputs
output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for Sentinel"
  value       = azurerm_log_analytics_workspace.sentinel.id
}

output "log_analytics_workspace_customer_id" {
  description = "Log Analytics Workspace Customer ID (used in queries)"
  value       = azurerm_log_analytics_workspace.sentinel.workspace_id
}

output "sentinel_workspace_id" {
  description = "Sentinel onboarding workspace ID"
  value       = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
}

output "brute_force_rule_id" {
  description = "Brute force analytics rule ID"
  value       = azurerm_sentinel_alert_rule_scheduled.brute_force.id
}

output "playbook_id" {
  description = "Logic App playbook ID"
  value       = azurerm_logic_app_workflow.sentinel_playbook.id
}

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

variable "resource_group_name" { default = "rg-eventhubs-lab" }
variable "location"            { default = "East US" }

resource "azurerm_resource_group" "eh" {
  name     = var.resource_group_name
  location = var.location
  tags = { project = "event-hubs-streaming", stage = "09", env = "lab" }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ── Event Hubs ────────────────────────────────────────────────────────────────

resource "azurerm_eventhub_namespace" "orders" {
  name                = "eh-orders-${random_string.suffix.result}"
  location            = azurerm_resource_group.eh.location
  resource_group_name = azurerm_resource_group.eh.name
  sku                 = "Standard"
  capacity            = 1  # 1 Throughput Unit

  auto_inflate_enabled     = false
  maximum_throughput_units = 0

  tags = azurerm_resource_group.eh.tags
}

resource "azurerm_eventhub" "orders" {
  name                = "orders-hub"
  namespace_name      = azurerm_eventhub_namespace.orders.name
  resource_group_name = azurerm_resource_group.eh.name
  partition_count     = 4
  message_retention   = 1  # 1 day retention
}

# Consumer group for Stream Analytics
resource "azurerm_eventhub_consumer_group" "analytics" {
  name                = "analytics-cg"
  namespace_name      = azurerm_eventhub_namespace.orders.name
  eventhub_name       = azurerm_eventhub.orders.name
  resource_group_name = azurerm_resource_group.eh.name
}

# Consumer group for application
resource "azurerm_eventhub_consumer_group" "app" {
  name                = "app-cg"
  namespace_name      = azurerm_eventhub_namespace.orders.name
  eventhub_name       = azurerm_eventhub.orders.name
  resource_group_name = azurerm_resource_group.eh.name
}

# Authorization rule for producer (Send only)
resource "azurerm_eventhub_authorization_rule" "producer" {
  name                = "producer-rule"
  namespace_name      = azurerm_eventhub_namespace.orders.name
  eventhub_name       = azurerm_eventhub.orders.name
  resource_group_name = azurerm_resource_group.eh.name
  listen              = false
  send                = true
  manage              = false
}

# Authorization rule for consumer (Listen only)
resource "azurerm_eventhub_authorization_rule" "consumer" {
  name                = "consumer-rule"
  namespace_name      = azurerm_eventhub_namespace.orders.name
  eventhub_name       = azurerm_eventhub.orders.name
  resource_group_name = azurerm_resource_group.eh.name
  listen              = true
  send                = false
  manage              = false
}

# ── Output Storage ────────────────────────────────────────────────────────────

resource "azurerm_storage_account" "output" {
  name                     = "stehout${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.eh.name
  location                 = azurerm_resource_group.eh.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true

  tags = azurerm_resource_group.eh.tags
}

resource "azurerm_storage_container" "output" {
  name                  = "output"
  storage_account_name  = azurerm_storage_account.output.name
  container_access_type = "private"
}

# ── Stream Analytics ──────────────────────────────────────────────────────────

resource "azurerm_stream_analytics_job" "orders" {
  name                                     = "asa-orders-aggregator"
  resource_group_name                      = azurerm_resource_group.eh.name
  location                                 = azurerm_resource_group.eh.location
  compatibility_level                      = "1.2"
  data_locale                              = "en-US"
  events_late_arrival_max_delay_in_seconds = 16
  events_out_of_order_max_delay_in_seconds = 5
  events_out_of_order_policy               = "Adjust"
  output_error_policy                      = "Drop"
  streaming_units                          = 1

  transformation_query = <<-SAQL
    SELECT
        product,
        COUNT(*) AS order_count,
        SUM(CAST(amount AS float)) AS total_revenue,
        AVG(CAST(amount AS float)) AS avg_order_value,
        MIN(CAST(amount AS float)) AS min_order,
        MAX(CAST(amount AS float)) AS max_order,
        System.Timestamp() AS window_end
    INTO [adls-output]
    FROM [orders-input] TIMESTAMP BY event_time
    GROUP BY
        product,
        TumblingWindow(Duration(minute, 1))
  SAQL

  tags = azurerm_resource_group.eh.tags
}

# Stream Analytics Input — Event Hub
resource "azurerm_stream_analytics_stream_input_eventhub" "orders" {
  name                         = "orders-input"
  stream_analytics_job_name    = azurerm_stream_analytics_job.orders.name
  resource_group_name          = azurerm_resource_group.eh.name
  eventhub_consumer_group_name = azurerm_eventhub_consumer_group.analytics.name
  eventhub_name                = azurerm_eventhub.orders.name
  servicebus_namespace         = azurerm_eventhub_namespace.orders.name
  shared_access_policy_key     = azurerm_eventhub_namespace.orders.default_primary_key
  shared_access_policy_name    = "RootManageSharedAccessKey"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Stream Analytics Output — ADLS Gen2
resource "azurerm_stream_analytics_output_blob" "adls" {
  name                      = "adls-output"
  stream_analytics_job_name = azurerm_stream_analytics_job.orders.name
  resource_group_name       = azurerm_resource_group.eh.name
  storage_account_name      = azurerm_storage_account.output.name
  storage_account_key       = azurerm_storage_account.output.primary_access_key
  storage_container_name    = azurerm_storage_container.output.name
  path_pattern              = "aggregated/{date}/{time}"
  date_format               = "yyyy/MM/dd"
  time_format               = "HH"
  batch_min_rows            = 0
  batch_max_wait_time       = "00:02:00"

  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "eventhub_namespace_name" {
  value = azurerm_eventhub_namespace.orders.name
}

output "eventhub_name" {
  value = azurerm_eventhub.orders.name
}

output "eventhub_connection_string_producer" {
  description = "Connection string for producer (Send only)"
  value       = azurerm_eventhub_authorization_rule.producer.primary_connection_string
  sensitive   = true
}

output "eventhub_connection_string_consumer" {
  description = "Connection string for consumer (Listen only)"
  value       = azurerm_eventhub_authorization_rule.consumer.primary_connection_string
  sensitive   = true
}

output "stream_analytics_job_name" {
  value = azurerm_stream_analytics_job.orders.name
}

output "output_storage_account_name" {
  value = azurerm_storage_account.output.name
}

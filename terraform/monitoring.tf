# Monitoring and Diagnostics Configuration
# Log Analytics workspace and diagnostic settings for Event Grid and Event Hub

# Log Analytics Workspace (centralized logging)
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-eventgrid-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.network.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Diagnostic Settings for Event Grid Topic
resource "azurerm_monitor_diagnostic_setting" "eventgrid" {
  name                       = "diag-eventgrid-to-logs"
  target_resource_id         = azurerm_eventgrid_topic.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Event Grid logs
  enabled_log {
    category = "DeliveryFailures"
  }

  enabled_log {
    category = "PublishFailures"
  }

  # Event Grid metrics
  enabled_metric {
    category = "AllMetrics"
  }
}

# Diagnostic Settings for Event Hub Namespace (conditional)
resource "azurerm_monitor_diagnostic_setting" "eventhub" {
  count                      = var.enable_dotnet_function && var.enable_event_hub ? 1 : 0
  name                       = "diag-eventhub-to-logs"
  target_resource_id         = azurerm_eventhub_namespace.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Event Hub logs
  enabled_log {
    category = "ArchiveLogs"
  }

  enabled_log {
    category = "OperationalLogs"
  }

  enabled_log {
    category = "AutoScaleLogs"
  }

  enabled_log {
    category = "KafkaCoordinatorLogs"
  }

  enabled_log {
    category = "KafkaUserErrorLogs"
  }

  enabled_log {
    category = "EventHubVNetConnectionEvent"
  }

  enabled_log {
    category = "CustomerManagedKeyUserLogs"
  }

  enabled_log {
    category = "RuntimeAuditLogs"
  }

  enabled_log {
    category = "ApplicationMetricsLogs"
  }

  # Event Hub metrics
  enabled_metric {
    category = "AllMetrics"
  }
}

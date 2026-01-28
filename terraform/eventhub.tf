# Event Hub infrastructure for fully private Event Grid delivery
# Conditional: Only deploy when enable_dotnet_function=true AND enable_event_hub=true

locals {
  deploy_eventhub = var.enable_dotnet_function && var.enable_event_hub
}

# Event Hub Resource Group (Subscription 1)
resource "azurerm_resource_group" "eventhub" {
  count    = local.deploy_eventhub ? 1 : 0
  name     = "${var.resource_group_prefix}-eventhub"
  location = var.location
  tags     = var.tags
}

# Event Hub Namespace (Standard SKU supports private endpoints)
# Configuration: Allows Event Grid delivery and private endpoint access
resource "azurerm_eventhub_namespace" "main" {
  count               = local.deploy_eventhub ? 1 : 0
  name                = "evhns-eventgrid-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventhub[0].name
  sku                 = "Standard"
  capacity            = 1
  tags                = var.tags

  network_rulesets {
    default_action                 = "Allow"
    trusted_service_access_enabled = true
  }
}

# Event Hub (the actual hub/topic within namespace)
resource "azurerm_eventhub" "events" {
  count             = local.deploy_eventhub ? 1 : 0
  name              = "events"
  namespace_id      = azurerm_eventhub_namespace.main[0].id
  partition_count   = 2
  message_retention = 1
}

# Private Endpoint in VNET2 (same subnet as Event Grid PE: 10.1.1.0/27)
resource "azurerm_private_endpoint" "eventhub" {
  count               = local.deploy_eventhub ? 1 : 0
  name                = "pe-eventhub-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventhub[0].name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "psc-eventhub"
    private_connection_resource_id = azurerm_eventhub_namespace.main[0].id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-eventhub"
    private_dns_zone_ids = [azurerm_private_dns_zone.eventhub[0].id]
  }

  tags       = var.tags
  depends_on = [azurerm_eventhub_namespace.main]
}

# Private DNS Zone for Event Hub
resource "azurerm_private_dns_zone" "eventhub" {
  count               = local.deploy_eventhub ? 1 : 0
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags
}

# DNS VNET Links (to all 3 VNETs for cross-subscription DNS resolution)
resource "azurerm_private_dns_zone_virtual_network_link" "eventhub_vnet1" {
  count                 = local.deploy_eventhub ? 1 : 0
  name                  = "vnet1-eventhub-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub[0].name
  virtual_network_id    = azurerm_virtual_network.function_vnet.id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhub_vnet2" {
  count                 = local.deploy_eventhub ? 1 : 0
  name                  = "vnet2-eventhub-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub[0].name
  virtual_network_id    = azurerm_virtual_network.eventgrid_vnet.id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhub_vnet3" {
  count                 = local.deploy_eventhub ? 1 : 0
  name                  = "vnet3-eventhub-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub[0].name
  virtual_network_id    = azurerm_virtual_network.dotnet_vnet[0].id
  tags                  = var.tags
}

# IAM: Event Grid → Event Hub (Data Sender)
resource "azurerm_role_assignment" "eventgrid_eventhub_sender" {
  count                = local.deploy_eventhub ? 1 : 0
  scope                = azurerm_eventhub_namespace.main[0].id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_eventgrid_topic.main.identity[0].principal_id
}

# IAM: .NET Function → Event Hub (Data Receiver)
resource "azurerm_role_assignment" "dotnet_function_eventhub_receiver" {
  count                = local.deploy_eventhub ? 1 : 0
  scope                = azurerm_eventhub_namespace.main[0].id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_linux_function_app.dotnet[0].identity[0].principal_id
}

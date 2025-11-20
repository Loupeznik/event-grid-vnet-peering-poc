resource "azurerm_eventgrid_topic" "main" {
  name                = "evgt-poc-${random_string.suffix.result}"
  location            = azurerm_resource_group.eventgrid.location
  resource_group_name = azurerm_resource_group.eventgrid.name

  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "eventgrid" {
  name                = "pe-eventgrid-${random_string.suffix.result}"
  location            = azurerm_resource_group.eventgrid.location
  resource_group_name = azurerm_resource_group.eventgrid.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "psc-eventgrid"
    private_connection_resource_id = azurerm_eventgrid_topic.main.id
    is_manual_connection           = false
    subresource_names              = ["topic"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-eventgrid"
    private_dns_zone_ids = [azurerm_private_dns_zone.eventgrid.id]
  }

  tags = var.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.eventgrid_vnet_link,
    azurerm_private_dns_zone_virtual_network_link.function_vnet_link
  ]
}

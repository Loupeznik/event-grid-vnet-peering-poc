resource "azurerm_private_dns_zone" "eventgrid" {
  name                = "privatelink.eventgrid.azure.net"
  resource_group_name = azurerm_resource_group.network.name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "function_vnet_link" {
  name                  = "vnet-function-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventgrid.name
  virtual_network_id    = azurerm_virtual_network.function_vnet.id
  registration_enabled  = false

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventgrid_vnet_link" {
  name                  = "vnet-eventgrid-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventgrid.name
  virtual_network_id    = azurerm_virtual_network.eventgrid_vnet.id
  registration_enabled  = false

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dotnet_vnet_link" {
  count = var.enable_dotnet_function ? 1 : 0

  name                  = "vnet-dotnet-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventgrid.name
  virtual_network_id    = azurerm_virtual_network.dotnet_vnet[0].id
  registration_enabled  = false

  tags = var.tags
}

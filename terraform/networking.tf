resource "azurerm_virtual_network" "function_vnet" {
  name                = "vnet-function-${random_string.suffix.result}"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = var.vnet1_address_space

  tags = var.tags
}

resource "azurerm_virtual_network" "eventgrid_vnet" {
  name                = "vnet-eventgrid-${random_string.suffix.result}"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = var.vnet2_address_space

  tags = var.tags
}

resource "azurerm_subnet" "function_subnet" {
  name                 = "snet-function"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.function_vnet.name
  address_prefixes     = var.function_subnet_prefix

  delegation {
    name = "function-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoint_subnet" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.eventgrid_vnet.name
  address_prefixes     = var.private_endpoint_subnet_prefix
}

resource "azurerm_virtual_network_peering" "function_to_eventgrid" {
  name                      = "peer-function-to-eventgrid"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.function_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.eventgrid_vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "eventgrid_to_function" {
  name                      = "peer-eventgrid-to-function"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.eventgrid_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.function_vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

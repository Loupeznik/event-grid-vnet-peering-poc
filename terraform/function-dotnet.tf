resource "azurerm_resource_group" "dotnet_network" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name     = "${var.resource_group_prefix}-dotnet-network"
  location = var.location

  tags = var.tags
}

resource "azurerm_resource_group" "dotnet_function" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name     = "${var.resource_group_prefix}-dotnet-function"
  location = var.location

  tags = var.tags
}

resource "azurerm_virtual_network" "dotnet_vnet" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name                = "vnet-dotnet-${random_string.suffix.result}"
  location            = azurerm_resource_group.dotnet_network[0].location
  resource_group_name = azurerm_resource_group.dotnet_network[0].name
  address_space       = var.vnet3_address_space

  tags = var.tags
}

resource "azurerm_subnet" "dotnet_function_subnet" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name                 = "snet-dotnet-function"
  resource_group_name  = azurerm_resource_group.dotnet_network[0].name
  virtual_network_name = azurerm_virtual_network.dotnet_vnet[0].name
  address_prefixes     = var.dotnet_function_subnet_prefix

  delegation {
    name = "dotnet-function-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

resource "azurerm_virtual_network_peering" "dotnet_to_eventgrid" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name                      = "peer-dotnet-to-eventgrid"
  resource_group_name       = azurerm_resource_group.dotnet_network[0].name
  virtual_network_name      = azurerm_virtual_network.dotnet_vnet[0].name
  remote_virtual_network_id = azurerm_virtual_network.eventgrid_vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [
    azurerm_subnet.dotnet_function_subnet,
    azurerm_subnet.private_endpoint_subnet
  ]
}

resource "azurerm_virtual_network_peering" "eventgrid_to_dotnet" {
  count = var.enable_dotnet_function ? 1 : 0

  name                      = "peer-eventgrid-to-dotnet"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.eventgrid_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.dotnet_vnet[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [
    azurerm_virtual_network_peering.dotnet_to_eventgrid,
    azurerm_subnet.dotnet_function_subnet,
    azurerm_subnet.private_endpoint_subnet
  ]
}

resource "azurerm_storage_account" "dotnet_function" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name                     = "stdotnetfn${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.dotnet_function[0].name
  location                 = azurerm_resource_group.dotnet_function[0].location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.tags
}

resource "azurerm_service_plan" "dotnet_function" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name                = "asp-dotnet-function-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dotnet_function[0].name
  location            = azurerm_resource_group.dotnet_function[0].location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku

  tags = var.tags
}

resource "azurerm_application_insights" "dotnet_function" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name                = "appi-dotnet-function-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dotnet_function[0].name
  location            = azurerm_resource_group.dotnet_function[0].location
  application_type    = "web"

  tags = var.tags
}

resource "azurerm_linux_function_app" "dotnet" {
  count    = var.enable_dotnet_function ? 1 : 0
  provider = azurerm.subscription2

  name                = "func-dotnet-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dotnet_function[0].name
  location            = azurerm_resource_group.dotnet_function[0].location

  storage_account_name       = azurerm_storage_account.dotnet_function[0].name
  storage_account_access_key = azurerm_storage_account.dotnet_function[0].primary_access_key
  service_plan_id            = azurerm_service_plan.dotnet_function[0].id

  virtual_network_subnet_id = azurerm_subnet.dotnet_function_subnet[0].id

  site_config {
    vnet_route_all_enabled          = true
    application_insights_connection_string = azurerm_application_insights.dotnet_function[0].connection_string

    application_stack {
      dotnet_version              = "10.0"
      use_dotnet_isolated_runtime = true
    }

    ip_restriction {
      name        = "Allow-EventGrid"
      service_tag = "AzureEventGrid"
      priority    = 100
      action      = "Allow"
    }

    ip_restriction {
      name        = "Allow-AzureCloud"
      service_tag = "AzureCloud"
      priority    = 110
      action      = "Allow"
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_addresses
      content {
        name       = "Allow-Custom-${ip_restriction.key}"
        ip_address = ip_restriction.value
        priority   = 200 + ip_restriction.key
        action     = "Allow"
      }
    }

    ip_restriction {
      name       = "Deny-All"
      ip_address = "0.0.0.0/0"
      priority   = 1000
      action     = "Deny"
    }
  }

  dynamic "auth_settings_v2" {
    for_each = var.enable_function_authentication ? [1] : []
    content {
      auth_enabled           = true
      unauthenticated_action = "AllowAnonymous"
      default_provider       = "AzureActiveDirectory"
      require_authentication = false
      require_https          = true

      active_directory_v2 {
        tenant_auth_endpoint = "https://login.microsoftonline.com/${var.entra_tenant_id != "" ? var.entra_tenant_id : data.azurerm_client_config.current.tenant_id}/v2.0"
        client_id            = azuread_application.dotnet_function[0].client_id
        allowed_audiences = [
          "https://${local.dotnet_function_hostname}",
          "api://${azuread_application.dotnet_function[0].client_id}"
        ]
      }

      login {
        token_store_enabled               = true
        preserve_url_fragments_for_logins = false
      }

      excluded_paths = [
        "/api/publish",
        "/runtime/webhooks/eventgrid"
      ]
    }
  }

  app_settings = merge(
    {
      "FUNCTIONS_WORKER_RUNTIME"                  = "dotnet-isolated"
      "EVENT_GRID_TOPIC_ENDPOINT"                 = azurerm_eventgrid_topic.main.endpoint
      "APPLICATIONINSIGHTS_CONNECTION_STRING"     = azurerm_application_insights.dotnet_function[0].connection_string
    },
    var.enable_event_hub ? {
      "EventHubConnection__fullyQualifiedNamespace" = "${azurerm_eventhub_namespace.main[0].name}.servicebus.windows.net"
      "EventHubConnection__credential"              = "managedidentity"
    } : {}
  )

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  depends_on = [
    azurerm_virtual_network_peering.dotnet_to_eventgrid,
    azurerm_virtual_network_peering.eventgrid_to_dotnet,
    azurerm_private_dns_zone_virtual_network_link.dotnet_vnet_link,
    azurerm_private_endpoint.eventgrid,
    time_sleep.wait_for_dotnet_storage_propagation
  ]
}

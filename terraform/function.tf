resource "azurerm_storage_account" "function" {
  name                     = "stfunc${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.function.name
  location                 = azurerm_resource_group.function.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.tags

  # Workaround for Azure data plane propagation delays
  # Ensures resource group is fully ready before storage account creation
  depends_on = [
    azurerm_resource_group.function
  ]

  lifecycle {
    # Ignore changes to access keys to prevent unnecessary updates
    ignore_changes = [
      tags["created_at"]
    ]
  }
}

resource "azurerm_service_plan" "function" {
  name                = "asp-function-${random_string.suffix.result}"
  location            = azurerm_resource_group.function.location
  resource_group_name = azurerm_resource_group.function.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku

  tags = var.tags
}

resource "azurerm_application_insights" "function" {
  name                = "appi-function-${random_string.suffix.result}"
  location            = azurerm_resource_group.function.location
  resource_group_name = azurerm_resource_group.function.name
  application_type    = "web"

  tags = var.tags
}

resource "azurerm_linux_function_app" "main" {
  name                = "func-eventgrid-${random_string.suffix.result}"
  location            = azurerm_resource_group.function.location
  resource_group_name = azurerm_resource_group.function.name

  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  service_plan_id            = azurerm_service_plan.function.id

  virtual_network_subnet_id = azurerm_subnet.function_subnet.id

  site_config {
    vnet_route_all_enabled = true
    application_stack {
      python_version = var.python_version
    }

    application_insights_connection_string = azurerm_application_insights.function.connection_string
    application_insights_key               = azurerm_application_insights.function.instrumentation_key

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
        client_id            = azuread_application.python_function[0].client_id
        allowed_audiences = [
          "https://${local.python_function_hostname}",
          "api://${azuread_application.python_function[0].client_id}"
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

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "EVENT_GRID_TOPIC_ENDPOINT"      = azurerm_eventgrid_topic.main.endpoint
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  depends_on = [
    azurerm_virtual_network_peering.function_to_eventgrid,
    azurerm_virtual_network_peering.eventgrid_to_function,
    azurerm_private_endpoint.eventgrid,
    time_sleep.wait_for_storage_propagation
  ]
}

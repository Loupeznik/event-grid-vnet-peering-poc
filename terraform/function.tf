resource "azurerm_storage_account" "function" {
  name                     = "stfunc${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.function.name
  location                 = azurerm_resource_group.function.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.tags
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
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "EVENT_GRID_TOPIC_ENDPOINT"      = azurerm_eventgrid_topic.main.endpoint
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  depends_on = [
    azurerm_virtual_network_peering.function_to_eventgrid,
    azurerm_virtual_network_peering.eventgrid_to_function,
    azurerm_private_endpoint.eventgrid
  ]
}

resource "azurerm_role_assignment" "dotnet_function_eventgrid_sender" {
  count = var.enable_dotnet_function ? 1 : 0

  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.dotnet[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "dotnet_function_eventgrid_contributor" {
  count = var.enable_dotnet_function ? 1 : 0

  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Contributor"
  principal_id         = azurerm_linux_function_app.dotnet[0].identity[0].principal_id
}

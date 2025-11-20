resource "azurerm_role_assignment" "function_eventgrid_data_sender" {
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_eventgrid_contributor" {
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

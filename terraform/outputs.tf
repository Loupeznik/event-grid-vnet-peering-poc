output "resource_group_network" {
  description = "Network resource group name"
  value       = azurerm_resource_group.network.name
}

output "resource_group_eventgrid" {
  description = "Event Grid resource group name"
  value       = azurerm_resource_group.eventgrid.name
}

output "resource_group_function" {
  description = "Function resource group name"
  value       = azurerm_resource_group.function.name
}

output "function_app_name" {
  description = "Function App name"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Function App default hostname"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "eventgrid_topic_name" {
  description = "Event Grid topic name"
  value       = azurerm_eventgrid_topic.main.name
}

output "eventgrid_topic_endpoint" {
  description = "Event Grid topic endpoint"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "eventgrid_private_endpoint_ip" {
  description = "Event Grid private endpoint IP address"
  value       = azurerm_private_endpoint.eventgrid.private_service_connection[0].private_ip_address
}

output "function_vnet_name" {
  description = "Function VNET name"
  value       = azurerm_virtual_network.function_vnet.name
}

output "eventgrid_vnet_name" {
  description = "Event Grid VNET name"
  value       = azurerm_virtual_network.eventgrid_vnet.name
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.function.connection_string
  sensitive   = true
}

output "function_principal_id" {
  description = "Function App managed identity principal ID"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

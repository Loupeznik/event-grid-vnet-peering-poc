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

output "enable_dotnet_function" {
  description = "Whether .NET function is enabled"
  value       = var.enable_dotnet_function
}

output "dotnet_subscription_id" {
  description = ".NET function subscription ID"
  value       = var.enable_dotnet_function ? var.subscription_id_2 : null
}

output "dotnet_resource_group_network" {
  description = ".NET network resource group name"
  value       = var.enable_dotnet_function ? azurerm_resource_group.dotnet_network[0].name : null
}

output "dotnet_resource_group_function" {
  description = ".NET function resource group name"
  value       = var.enable_dotnet_function ? azurerm_resource_group.dotnet_function[0].name : null
}

output "dotnet_function_app_name" {
  description = ".NET Function App name"
  value       = var.enable_dotnet_function ? azurerm_linux_function_app.dotnet[0].name : null
}

output "dotnet_function_app_default_hostname" {
  description = ".NET Function App default hostname"
  value       = var.enable_dotnet_function ? azurerm_linux_function_app.dotnet[0].default_hostname : null
}

output "dotnet_function_principal_id" {
  description = ".NET Function App managed identity principal ID"
  value       = var.enable_dotnet_function ? azurerm_linux_function_app.dotnet[0].identity[0].principal_id : null
}

output "dotnet_vnet_name" {
  description = ".NET VNET name"
  value       = var.enable_dotnet_function ? azurerm_virtual_network.dotnet_vnet[0].name : null
}

output "dotnet_application_insights_connection_string" {
  description = ".NET Application Insights connection string"
  value       = var.enable_dotnet_function ? azurerm_application_insights.dotnet_function[0].connection_string : null
  sensitive   = true
}

output "vnet_peering_names" {
  description = "VNET peering resource names"
  value = var.enable_dotnet_function ? {
    function_to_eventgrid  = azurerm_virtual_network_peering.function_to_eventgrid.name
    eventgrid_to_function  = azurerm_virtual_network_peering.eventgrid_to_function.name
    dotnet_to_eventgrid    = azurerm_virtual_network_peering.dotnet_to_eventgrid[0].name
    eventgrid_to_dotnet    = azurerm_virtual_network_peering.eventgrid_to_dotnet[0].name
  } : {
    function_to_eventgrid = azurerm_virtual_network_peering.function_to_eventgrid.name
    eventgrid_to_function = azurerm_virtual_network_peering.eventgrid_to_function.name
  }
}

output "authentication_enabled" {
  description = "Whether Entra ID authentication is enabled on functions"
  value       = var.enable_function_authentication
}

output "python_function_client_id" {
  description = "Python function Entra ID app client ID"
  value       = var.enable_function_authentication ? azuread_application.python_function[0].client_id : null
}

output "dotnet_function_client_id" {
  description = ".NET function Entra ID app client ID"
  value       = var.enable_dotnet_function && var.enable_function_authentication ? azuread_application.dotnet_function[0].client_id : null
}


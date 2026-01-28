data "azurerm_client_config" "current" {}

locals {
  python_function_hostname = "func-eventgrid-${random_string.suffix.result}.azurewebsites.net"
  dotnet_function_hostname = "func-dotnet-${random_string.suffix.result}.azurewebsites.net"
}

resource "azuread_application" "python_function" {
  count        = var.enable_function_authentication ? 1 : 0
  display_name = "func-python-${random_string.suffix.result}"
  owners       = [data.azurerm_client_config.current.object_id]

  web {
    homepage_url = "https://${local.python_function_hostname}"
    redirect_uris = [
      "https://${local.python_function_hostname}/.auth/login/aad/callback"
    ]

    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }
}

resource "azuread_service_principal" "python_function" {
  count     = var.enable_function_authentication ? 1 : 0
  client_id = azuread_application.python_function[0].client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application" "dotnet_function" {
  count        = var.enable_dotnet_function && var.enable_function_authentication ? 1 : 0
  display_name = "func-dotnet-${random_string.suffix.result}"
  owners       = [data.azurerm_client_config.current.object_id]

  web {
    homepage_url = "https://${local.dotnet_function_hostname}"
    redirect_uris = [
      "https://${local.dotnet_function_hostname}/.auth/login/aad/callback"
    ]

    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }
}

resource "azuread_service_principal" "dotnet_function" {
  count     = var.enable_dotnet_function && var.enable_function_authentication ? 1 : 0
  client_id = azuread_application.dotnet_function[0].client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

# Note: System topics are only for Azure resource events (Storage, Resource Groups, etc.)
# Custom Event Grid topics use webhook validation instead of managed identity authentication
# The Function App's Entra ID authentication will validate incoming requests
# Event Grid automatically handles webhook validation during subscription creation

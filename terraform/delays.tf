# Workaround for Azure data plane propagation delays
# Azure has two API planes:
# - Control Plane: Creates/manages resources (fast)
# - Data Plane: Provides access to resource data like storage keys (slower)
#
# After creating storage accounts, Azure needs time to propagate to the data plane
# before Terraform can retrieve keys. This delay resource ensures proper timing.

resource "time_sleep" "wait_for_storage_propagation" {
  depends_on = [
    azurerm_storage_account.function
  ]

  create_duration = "30s"

  triggers = {
    storage_account_id = azurerm_storage_account.function.id
  }
}

resource "time_sleep" "wait_for_dotnet_storage_propagation" {
  count = var.enable_dotnet_function ? 1 : 0

  depends_on = [
    azurerm_storage_account.dotnet_function
  ]

  create_duration = "30s"

  triggers = {
    storage_account_id = azurerm_storage_account.dotnet_function[0].id
  }
}

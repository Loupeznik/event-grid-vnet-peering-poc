variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "swedencentral"
}

variable "resource_group_prefix" {
  description = "Prefix for resource group names"
  type        = string
  default     = "rg-eventgrid-vnet-poc"
}

variable "vnet1_address_space" {
  description = "Address space for VNET 1 (Function VNET)"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "vnet2_address_space" {
  description = "Address space for VNET 2 (Event Grid VNET)"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "function_subnet_prefix" {
  description = "Address prefix for Function subnet"
  type        = list(string)
  default     = ["10.0.1.0/27"]
}

variable "private_endpoint_subnet_prefix" {
  description = "Address prefix for Private Endpoint subnet"
  type        = list(string)
  default     = ["10.1.1.0/27"]
}

variable "app_service_plan_sku" {
  description = "SKU for App Service Plan"
  type        = string
  default     = "B1"
}

variable "python_version" {
  description = "Python version for Function App"
  type        = string
  default     = "3.11"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "PoC"
    Project     = "EventGrid-VNET-Peering"
    ManagedBy   = "Terraform"
  }
}

variable "enable_dotnet_function" {
  description = "Enable .NET function deployment in second subscription"
  type        = bool
  default     = false
}

variable "subscription_id_2" {
  description = "Azure subscription ID for .NET function (Subscription 2)"
  type        = string
  default     = ""

  validation {
    condition     = var.enable_dotnet_function == false || var.subscription_id_2 != ""
    error_message = "subscription_id_2 must be provided when enable_dotnet_function is true."
  }
}

variable "vnet3_address_space" {
  description = "Address space for VNET 3 (.NET Function VNET)"
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

variable "dotnet_function_subnet_prefix" {
  description = "Address prefix for .NET Function subnet"
  type        = list(string)
  default     = ["10.2.1.0/27"]
}

variable "allowed_ip_addresses" {
  description = "List of IP addresses or CIDR blocks allowed to access Function Apps (in addition to Event Grid service tag)"
  type        = list(string)
  default     = []
}

variable "enable_function_authentication" {
  description = "Enable Entra ID authentication on Function Apps"
  type        = bool
  default     = true
}

variable "entra_tenant_id" {
  description = "Azure AD (Entra ID) tenant ID for authentication. If not provided, uses current tenant."
  type        = string
  default     = ""
}

variable "enable_event_hub" {
  description = "Enable Event Hub delivery for .NET function (requires enable_dotnet_function=true)"
  type        = bool
  default     = false

  validation {
    condition     = var.enable_event_hub == false || var.enable_dotnet_function == true
    error_message = "enable_event_hub requires enable_dotnet_function to be true. Event Hub is only used for .NET function delivery."
  }
}

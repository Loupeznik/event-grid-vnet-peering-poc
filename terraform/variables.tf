variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "northeurope"
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

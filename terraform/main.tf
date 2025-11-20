terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription_id
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "network" {
  name     = "${var.resource_group_prefix}-network"
  location = var.location

  tags = var.tags
}

resource "azurerm_resource_group" "eventgrid" {
  name     = "${var.resource_group_prefix}-eventgrid"
  location = var.location

  tags = var.tags
}

resource "azurerm_resource_group" "function" {
  name     = "${var.resource_group_prefix}-function"
  location = var.location

  tags = var.tags
}

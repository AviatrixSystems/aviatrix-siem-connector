terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source = "hashicorp/azuread"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}

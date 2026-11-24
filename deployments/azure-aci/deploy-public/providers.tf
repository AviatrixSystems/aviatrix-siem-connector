terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}

# Provider environments follow var.azure_cloud so that AzureUSGovernment
# targets the US Government cloud for Terraform as well as for the plugin.
# (Azure China uses ../deploy-china.)
locals {
  is_usgov          = var.azure_cloud == "AzureUSGovernment"
  azurerm_env       = local.is_usgov ? "usgovernment" : "public"
  azuread_env       = local.is_usgov ? "usgovernment" : "global"
  azapi_environment = local.is_usgov ? "usgovernment" : "public"
}

provider "azurerm" {
  features {}
  alias       = "public"
  environment = local.azurerm_env
}

# Log Analytics provider (same or different subscription)
provider "azurerm" {
  features {}
  alias           = "loganalytics"
  environment     = local.azurerm_env
  subscription_id = var.log_analytics_subscription_id == "dummy" ? data.azurerm_client_config.current.subscription_id : var.log_analytics_subscription_id
}

provider "azuread" {
  alias       = "public"
  environment = local.azuread_env
}

provider "azapi" {
  environment = local.azapi_environment
}

# Terraform configuration file for EntraID Service Principal and Role Assignments
# This is optional if you want to use an existing Service Principal instead of creating a new one
# This is managed by variable "use_existing_spn"

data "azuread_client_config" "current" {
  count = var.use_existing_spn ? 0 : 1
}

data "azurerm_client_config" "current" {}

# If using an existing Service Principal, we need to retrieve its object ID
data "azuread_service_principal" "existing_client_app_id" {
  count     = var.use_existing_spn ? 1 : 0
  client_id = var.client_app_id
}

# 1. Application (Service Principal) creation
resource "azuread_application" "logstash_app" {
  count        = var.use_existing_spn ? 0 : 1
  display_name = "aviatrix-logstash-sentinel-${random_integer.suffix.result}"
  owners       = [data.azuread_client_config.current[0].object_id]
}

resource "azuread_application_password" "logstash_app_password" {
  count          = var.use_existing_spn ? 0 : 1
  application_id = azuread_application.logstash_app[0].id
  end_date       = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [end_date]
  }
}

resource "azuread_service_principal" "logstash_sp" {
  count     = var.use_existing_spn ? 0 : 1
  client_id = azuread_application.logstash_app[0].client_id
  owners    = [data.azuread_client_config.current[0].object_id]
}

resource "azuread_service_principal_password" "logstash_sp_password" {
  count                = var.use_existing_spn ? 0 : 1
  service_principal_id = azuread_service_principal.logstash_sp[0].id
}

# Role assignments for the Log Analytics Data Collection Rules

resource "azurerm_role_assignment" "aviatrix_ids_dcr_assignment" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.aci_rg.name}/providers/Microsoft.Insights/dataCollectionRules/aviatrix-ids-dcr"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
  depends_on           = [azurerm_monitor_data_collection_rule.aviatrix_ids]
}

resource "azurerm_role_assignment" "aviatrix_netsession_dcr_assignment" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.aci_rg.name}/providers/Microsoft.Insights/dataCollectionRules/aviatrix-netsession-dcr"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
  depends_on           = [azurerm_monitor_data_collection_rule.aviatrix_netsession]
}

resource "azurerm_role_assignment" "aviatrix_websession_dcr_assignment" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.aci_rg.name}/providers/Microsoft.Insights/dataCollectionRules/aviatrix-websession-dcr"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
  depends_on           = [azurerm_monitor_data_collection_rule.aviatrix_websession]
}

resource "azurerm_role_assignment" "aviatrix_gw_net_stats_dcr_assignment" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.aci_rg.name}/providers/Microsoft.Insights/dataCollectionRules/aviatrix-gw-net-stats-dcr"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
  depends_on           = [azurerm_monitor_data_collection_rule.aviatrix_gw_net_stats]
}

resource "azurerm_role_assignment" "aviatrix_gw_sys_stats_dcr_assignment" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.aci_rg.name}/providers/Microsoft.Insights/dataCollectionRules/aviatrix-gw-sys-stats-dcr"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
  depends_on           = [azurerm_monitor_data_collection_rule.aviatrix_gw_sys_stats]
}

resource "azurerm_role_assignment" "aviatrix_cmd_dcr_assignment" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.aci_rg.name}/providers/Microsoft.Insights/dataCollectionRules/aviatrix-cmd-dcr"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
  depends_on           = [azurerm_monitor_data_collection_rule.aviatrix_cmd]
}

resource "azurerm_role_assignment" "aviatrix_tunnel_status_dcr_assignment" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.aci_rg.name}/providers/Microsoft.Insights/dataCollectionRules/aviatrix-tunnel-status-dcr"
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
  depends_on           = [azurerm_monitor_data_collection_rule.aviatrix_tunnel_status]
}

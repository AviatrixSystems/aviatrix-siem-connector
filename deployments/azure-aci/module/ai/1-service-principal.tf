# Terraform configuration file for EntraID Service Principal and Role Assignments
# This is optional if you want to use an existing Service Principal instead of creating a new one
# This is managed by variable "use_existing_spn"

data "azuread_client_config" "current" {
  count = var.use_existing_spn ? 0 : 1
}

# If using an existing Service Principal, we need to retrieve its object ID
data "azuread_service_principal" "existing_client_app_id" {
  count     = var.use_existing_spn ? 1 : 0
  client_id = var.client_app_id

  lifecycle {
    precondition {
      condition     = var.client_app_id != null && var.client_app_secret != null && var.tenant_id != null
      error_message = "use_existing_spn = true requires client_app_id, client_app_secret and tenant_id to all be set. Set use_existing_spn = false to let Terraform create the service principal instead."
    }
  }
}

# 1. Application (Service Principal) creation
resource "azuread_application" "logstash_app" {
  count        = var.use_existing_spn ? 0 : 1
  display_name = "aviatrix-logstash-sentinel-${random_integer.suffix.result}"
  owners       = [data.azuread_client_config.current[0].object_id]
}

# Secret rotation: time_rotating rolls over every spn_secret_rotation_days.
# The first `terraform apply` after that date mints a new secret (and
# recreates the container with it). The secret stays valid for an extra
# 30-day grace period, so an apply must run within that window or ingestion
# stops with 401s from Entra ID.
resource "time_rotating" "logstash_app_password" {
  count         = var.use_existing_spn ? 0 : 1
  rotation_days = var.spn_secret_rotation_days
}

resource "azuread_application_password" "logstash_app_password" {
  count          = var.use_existing_spn ? 0 : 1
  application_id = azuread_application.logstash_app[0].id
  end_date       = timeadd(time_rotating.logstash_app_password[0].rotation_rfc3339, "720h")

  rotate_when_changed = {
    rotation = time_rotating.logstash_app_password[0].id
  }
}

resource "azuread_service_principal" "logstash_sp" {
  count     = var.use_existing_spn ? 0 : 1
  client_id = azuread_application.logstash_app[0].client_id
  owners    = [data.azuread_client_config.current[0].object_id]
}

# Role assignments for the Log Analytics Data Collection Rules

resource "azurerm_role_assignment" "aviatrix_ids_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_ids.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

resource "azurerm_role_assignment" "aviatrix_netsession_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_netsession.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

resource "azurerm_role_assignment" "aviatrix_websession_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_websession.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

resource "azurerm_role_assignment" "aviatrix_gw_net_stats_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_gw_net_stats.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

resource "azurerm_role_assignment" "aviatrix_gw_sys_stats_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_gw_sys_stats.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

resource "azurerm_role_assignment" "aviatrix_cmd_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_cmd.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

resource "azurerm_role_assignment" "aviatrix_tunnel_status_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_tunnel_status.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

resource "azurerm_role_assignment" "aviatrix_vpn_session_dcr_assignment" {
  scope                = azurerm_monitor_data_collection_rule.aviatrix_vpn_session.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.use_existing_spn ? data.azuread_service_principal.existing_client_app_id[0].object_id : azuread_service_principal.logstash_sp[0].object_id
}

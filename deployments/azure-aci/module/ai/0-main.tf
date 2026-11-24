# Resource group for the container instance
resource "azurerm_resource_group" "aci_rg" {
  name     = var.resource_group_name
  location = var.location
}

# Generate random suffix for unique naming
resource "random_integer" "suffix" {
  min = 10000
  max = 99999
}

# Storage account for Logstash configuration files
resource "azurerm_storage_account" "logstash_storage" {
  name                     = "${var.storage_account_name}${random_integer.suffix.result}"
  resource_group_name      = azurerm_resource_group.aci_rg.name
  location                 = azurerm_resource_group.aci_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.tags
}

# File share for Logstash patterns
resource "azurerm_storage_share" "patterns" {
  name                 = "patterns"
  storage_account_name = azurerm_storage_account.logstash_storage.name
  quota                = var.file_share_quota_gb
}

# File share for Logstash pipeline
resource "azurerm_storage_share" "pipeline" {
  name                 = "pipeline"
  storage_account_name = azurerm_storage_account.logstash_storage.name
  quota                = var.file_share_quota_gb
}

locals {
  logstash_conf_path = "${path.module}/../../../../logstash-configs/assembled/azure-log-ingestion-full.conf"
  avx_pattern_path   = "${path.module}/../../../../logstash-configs/patterns/avx.conf"
}

# Upload Logstash configuration file to the pipeline share.
# content_md5 makes Terraform re-upload the file whenever its content changes
# (without it, edits at the same path produce an empty plan). The running
# container picks the new file up via CONFIG_RELOAD_AUTOMATIC.
resource "azurerm_storage_share_file" "logstash_conf" {
  name             = "logstash.conf"
  storage_share_id = azurerm_storage_share.pipeline.id
  source           = local.logstash_conf_path
  content_md5      = filemd5(local.logstash_conf_path)
  depends_on       = [azurerm_monitor_data_collection_endpoint.dce]
}

# Upload pattern file to the patterns share
resource "azurerm_storage_share_file" "avx_pattern" {
  name             = "avx.conf"
  storage_share_id = azurerm_storage_share.patterns.id
  source           = local.avx_pattern_path
  content_md5      = filemd5(local.avx_pattern_path)
}

# Container group with Logstash container
#
# SECURITY NOTE: ip_address_type = "Public" exposes the unauthenticated syslog
# port to the Internet. ACI public IPs cannot carry an NSG, so there is no
# source-IP filtering. See deployments/azure-aci/README.md ("Network exposure")
# for the VNet-injected alternative.
resource "azurerm_container_group" "logstash" {
  name                = "${var.container_name}-group"
  location            = azurerm_resource_group.aci_rg.location
  resource_group_name = azurerm_resource_group.aci_rg.name
  ip_address_type     = "Public"
  dns_name_label      = "${var.container_name}-${random_integer.suffix.result}"
  os_type             = "Linux"

  # Optional private registry credentials (avoids enabling anonymous pull on ACR)
  dynamic "image_registry_credential" {
    for_each = var.container_registry_server == null ? [] : [1]
    content {
      server   = var.container_registry_server
      username = var.container_registry_username
      password = var.container_registry_password
    }
  }

  container {
    name   = var.container_name
    image  = var.container_image
    cpu    = var.cpu_cores
    memory = var.memory_gb

    ports {
      port     = var.container_port
      protocol = var.container_protocol
    }

    environment_variables = merge(var.environment_variables, {
      # DCR immutable IDs (computed by Terraform)
      "azure_dcr_netsession_id"    = azurerm_monitor_data_collection_rule.aviatrix_netsession.immutable_id
      "azure_dcr_websession_id"    = azurerm_monitor_data_collection_rule.aviatrix_websession.immutable_id
      "azure_dcr_ids_id"           = azurerm_monitor_data_collection_rule.aviatrix_ids.immutable_id
      "azure_dcr_gw_net_stats_id"  = azurerm_monitor_data_collection_rule.aviatrix_gw_net_stats.immutable_id
      "azure_dcr_gw_sys_stats_id"  = azurerm_monitor_data_collection_rule.aviatrix_gw_sys_stats.immutable_id
      "azure_dcr_cmd_id"           = azurerm_monitor_data_collection_rule.aviatrix_cmd.immutable_id
      "azure_dcr_tunnel_status_id" = azurerm_monitor_data_collection_rule.aviatrix_tunnel_status.immutable_id
      "azure_dcr_vpn_session_id"   = azurerm_monitor_data_collection_rule.aviatrix_vpn_session.immutable_id
      # Stream names (must match DCR stream definitions)
      "azure_stream_netsession"    = "Custom-AviatrixNetworkSession_CL"
      "azure_stream_websession"    = "Custom-AviatrixWebSession_CL"
      "azure_stream_ids"           = "Custom-AviatrixIDS_CL"
      "azure_stream_gw_net_stats"  = "Custom-AviatrixGwNetStats_CL"
      "azure_stream_gw_sys_stats"  = "Custom-AviatrixGwSysStats_CL"
      "azure_stream_cmd"           = "Custom-AviatrixCmd_CL"
      "azure_stream_tunnel_status" = "Custom-AviatrixTunnelStatus_CL"
      "azure_stream_vpn_session"   = "Custom-AviatrixVPNSession_CL"
      # Authentication and endpoint (computed or from variables)
      "data_collection_endpoint" = azurerm_monitor_data_collection_endpoint.dce.logs_ingestion_endpoint
      "client_app_id"            = var.use_existing_spn ? var.client_app_id : azuread_application.logstash_app[0].client_id
      "tenant_id"                = var.use_existing_spn ? var.tenant_id : data.azuread_client_config.current[0].tenant_id
      # Azure cloud environment — plugin expects AzureCloud, AzureChinaCloud, or AzureUSGovernment
      "azure_cloud" = var.azure_cloud
    })

    # The SPN secret is passed as a secure env var so it is not returned by
    # `az container show` or shown in the portal to resource-group readers.
    secure_environment_variables = {
      "client_app_secret" = var.use_existing_spn ? var.client_app_secret : azuread_application_password.logstash_app_password[0].value
    }

    volume {
      name                 = "logstash-patterns"
      mount_path           = "/usr/share/logstash/patterns"
      read_only            = false
      storage_account_name = azurerm_storage_account.logstash_storage.name
      storage_account_key  = azurerm_storage_account.logstash_storage.primary_access_key
      share_name           = azurerm_storage_share.patterns.name
    }

    volume {
      name                 = "logstash-pipeline"
      mount_path           = "/usr/share/logstash/pipeline"
      read_only            = false
      storage_account_name = azurerm_storage_account.logstash_storage.name
      storage_account_key  = azurerm_storage_account.logstash_storage.primary_access_key
      share_name           = azurerm_storage_share.pipeline.name
    }
  }

  diagnostics {
    log_analytics {
      workspace_id  = var.log_analytics_workspace.workspace_id
      workspace_key = var.log_analytics_workspace.primary_shared_key
    }
  }

  tags       = var.tags
  depends_on = [azurerm_storage_share_file.avx_pattern, azurerm_storage_share_file.logstash_conf]
}

# Terraform configuration file for Azure Monitor Data Collection Rules and related resources

## Data Collection Endpoint used as entry point for Data Collection Rules
resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "avx-drc-${random_integer.suffix.result}"
  location            = azurerm_resource_group.aci_rg.location
  resource_group_name = azurerm_resource_group.aci_rg.name

}

## Data Collection Rule for Aviatrix L4 Network Session (ASIM NetworkSession)
resource "azurerm_monitor_data_collection_rule" "aviatrix_netsession" {
  name                        = "aviatrix-netsession-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_netsession]

  data_flow {
    streams       = ["Custom-AviatrixNetworkSession_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixNetworkSession_CL"
    transform_kql = local.dcr_transform_kql.netsession
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixNetworkSession_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.netsession
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

## Data Collection Rule for Aviatrix L7 Web Session (ASIM WebSession)
resource "azurerm_monitor_data_collection_rule" "aviatrix_websession" {
  name                        = "aviatrix-websession-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_websession]

  data_flow {
    streams       = ["Custom-AviatrixWebSession_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixWebSession_CL"
    transform_kql = local.dcr_transform_kql.websession
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixWebSession_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.websession
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

## Data Collection Rule for Aviatrix IDS (Suricata) logs (ASIM NetworkSession, EventType=IDS)
resource "azurerm_monitor_data_collection_rule" "aviatrix_ids" {
  name                        = "aviatrix-ids-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_ids]

  data_flow {
    streams       = ["Custom-AviatrixIDS_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixIDS_CL"
    transform_kql = local.dcr_transform_kql.ids
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixIDS_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.ids
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

## Data Collection Rule for Aviatrix Gateway Network Stats
resource "azurerm_monitor_data_collection_rule" "aviatrix_gw_net_stats" {
  name                        = "aviatrix-gw-net-stats-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_gw_net_stats]

  data_flow {
    streams       = ["Custom-AviatrixGwNetStats_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixGwNetStats_CL"
    transform_kql = local.dcr_transform_kql.gw_net_stats
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixGwNetStats_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.gw_net_stats
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

## Data Collection Rule for Aviatrix Gateway System Stats
resource "azurerm_monitor_data_collection_rule" "aviatrix_gw_sys_stats" {
  name                        = "aviatrix-gw-sys-stats-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_gw_sys_stats]

  data_flow {
    streams       = ["Custom-AviatrixGwSysStats_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixGwSysStats_CL"
    transform_kql = local.dcr_transform_kql.gw_sys_stats
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixGwSysStats_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.gw_sys_stats
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

## Data Collection Rule for Aviatrix Controller CMD/API logs
resource "azurerm_monitor_data_collection_rule" "aviatrix_cmd" {
  name                        = "aviatrix-cmd-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_cmd]

  data_flow {
    streams       = ["Custom-AviatrixCmd_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixCmd_CL"
    transform_kql = local.dcr_transform_kql.cmd
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixCmd_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.cmd
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

## Data Collection Rule for Aviatrix Tunnel Status Changes
resource "azurerm_monitor_data_collection_rule" "aviatrix_tunnel_status" {
  name                        = "aviatrix-tunnel-status-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_tunnel_status]

  data_flow {
    streams       = ["Custom-AviatrixTunnelStatus_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixTunnelStatus_CL"
    transform_kql = local.dcr_transform_kql.tunnel_status
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixTunnelStatus_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.tunnel_status
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

## Data Collection Rule for Aviatrix VPN Session (connect/disconnect, non-ASIM passthrough)
resource "azurerm_monitor_data_collection_rule" "aviatrix_vpn_session" {
  name                        = "aviatrix-vpn-session-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_vpn_session]

  data_flow {
    streams       = ["Custom-AviatrixVPNSession_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixVPNSession_CL"
    transform_kql = local.dcr_transform_kql.vpn_session
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixVPNSession_CL"
    # Columns are defined once in 4-table-schemas.tf
    dynamic "column" {
      for_each = local.stream_schemas.vpn_session
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }
}

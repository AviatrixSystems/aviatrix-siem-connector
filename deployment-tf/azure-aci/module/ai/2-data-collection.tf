# Terraform configuration file for Azure Monitor Data Collection Rules and related resources

## Data Collection Endpoint used as entry point for Data Collection Rules
resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "avx-drc-${random_integer.suffix.result}"
  location            = azurerm_resource_group.aci_rg.location
  resource_group_name = azurerm_resource_group.aci_rg.name

}

## Data Collection Rule for Aviatrix Microseg/MITM logs
resource "azurerm_monitor_data_collection_rule" "aviatrix_microseg" {
  name                        = "aviatrix-microseg-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_microseg]

  data_flow {
    streams       = ["Custom-AviatrixMicroseg_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixMicroseg_CL"
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixMicroseg_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "action"
      type = "string"
    }
    column {
      name = "dst_ip"
      type = "string"
    }
    column {
      name = "dst_mac"
      type = "string"
    }
    column {
      name = "dst_port"
      type = "int"
    }
    column {
      name = "enforced"
      type = "boolean"
    }
    column {
      name = "gw_hostname"
      type = "string"
    }
    column {
      name = "gw_ip"
      type = "string"
    }
    column {
      name = "ip_size"
      type = "int"
    }
    column {
      name = "ls_timestamp"
      type = "string"
    }
    column {
      name = "mitm_decrypted_by"
      type = "string"
    }
    column {
      name = "mitm_sni_hostname"
      type = "string"
    }
    column {
      name = "mitm_url_parts"
      type = "string"
    }
    column {
      name = "proto"
      type = "string"
    }
    column {
      name = "session_byte_cnt"
      type = "long"
    }
    column {
      name = "session_dur"
      type = "long"
    }
    column {
      name = "session_end_reason"
      type = "int"
    }
    column {
      name = "session_event"
      type = "int"
    }
    column {
      name = "session_id"
      type = "long"
    }
    column {
      name = "session_pkt_cnt"
      type = "long"
    }
    column {
      name = "src_ip"
      type = "string"
    }
    column {
      name = "src_mac"
      type = "string"
    }
    column {
      name = "src_port"
      type = "int"
    }
    column {
      name = "tags"
      type = "dynamic"
    }
    column {
      name = "unix_time"
      type = "long"
    }
    column {
      name = "uuid"
      type = "string"
    }
  }
}

## Data Collection Rule for Aviatrix IDS (Suricata) logs
resource "azurerm_monitor_data_collection_rule" "aviatrix_suricata" {
  name                        = "aviatrix-suricata-dcr"
  location                    = azurerm_resource_group.aci_rg.location
  resource_group_name         = azurerm_resource_group.aci_rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  depends_on = [azapi_resource.table_suricata]

  data_flow {
    streams       = ["Custom-AviatrixSuricata_CL"]
    destinations  = ["loganalytics-destination"]
    output_stream = "Custom-AviatrixSuricata_CL"
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixSuricata_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "Computer"
      type = "string"
    }
    column {
      name = "alert"
      type = "dynamic"
    }
    column {
      name = "app_proto"
      type = "string"
    }
    column {
      name = "dest_ip"
      type = "string"
    }
    column {
      name = "dest_port"
      type = "int"
    }
    column {
      name = "event_type"
      type = "string"
    }
    column {
      name = "files"
      type = "dynamic"
    }
    column {
      name = "flow"
      type = "dynamic"
    }
    column {
      name = "flow_id"
      type = "long"
    }
    column {
      name = "http"
      type = "dynamic"
    }
    column {
      name = "in_iface"
      type = "string"
    }
    column {
      name = "ls_timestamp"
      type = "string"
    }
    column {
      name = "ls_version"
      type = "string"
    }
    column {
      name = "proto"
      type = "string"
    }
    column {
      name = "src_ip"
      type = "string"
    }
    column {
      name = "src_port"
      type = "int"
    }
    column {
      name = "tags"
      type = "dynamic"
    }
    column {
      name = "timestamp"
      type = "string"
    }
    column {
      name = "tx_id"
      type = "int"
    }
    column {
      name = "unix_time"
      type = "long"
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
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixGwNetStats_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "alias"
      type = "string"
    }
    column {
      name = "bw_in_limit_exceeded"
      type = "int"
    }
    column {
      name = "bw_out_limit_exceeded"
      type = "int"
    }
    column {
      name = "conntrack_allowance_available"
      type = "int"
    }
    column {
      name = "conntrack_count"
      type = "int"
    }
    column {
      name = "conntrack_limit_exceeded"
      type = "int"
    }
    column {
      name = "conntrack_usage_rate"
      type = "int"
    }
    column {
      name = "gateway"
      type = "string"
    }
    column {
      name = "interface"
      type = "string"
    }
    column {
      name = "linklocal_limit_exceeded"
      type = "int"
    }
    column {
      name = "ls_timestamp"
      type = "string"
    }
    column {
      name = "pps_limit_exceeded"
      type = "int"
    }
    column {
      name = "private_ip"
      type = "string"
    }
    column {
      name = "public_ip"
      type = "string"
    }
    column {
      name = "tags"
      type = "dynamic"
    }
    column {
      name = "total_rx_cum"
      type = "string"
    }
    column {
      name = "total_rx_rate"
      type = "int"
    }
    column {
      name = "total_rx_tx_cum"
      type = "string"
    }
    column {
      name = "total_rx_tx_rate"
      type = "int"
    }
    column {
      name = "total_tx_cum"
      type = "string"
    }
    column {
      name = "total_tx_rate"
      type = "int"
    }
    column {
      name = "unix_time"
      type = "long"
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
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixGwSysStats_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "alias"
      type = "string"
    }
    column {
      name = "cpu_aggregate_busy_avg"
      type = "int"
    }
    column {
      name = "cpu_aggregate_busy_max"
      type = "int"
    }
    column {
      name = "cpu_aggregate_busy_min"
      type = "int"
    }
    column {
      name = "cpu_busy"
      type = "real"
    }
    column {
      name = "cpu_core_count"
      type = "int"
    }
    column {
      name = "cpu_cores_parsed"
      type = "dynamic"
    }
    column {
      name = "cpu_idle"
      type = "real"
    }
    column {
      name = "disk_free"
      type = "int"
    }
    column {
      name = "disk_total"
      type = "int"
    }
    column {
      name = "gateway"
      type = "string"
    }
    column {
      name = "ls_timestamp"
      type = "string"
    }
    column {
      name = "memory_available"
      type = "int"
    }
    column {
      name = "memory_free"
      type = "int"
    }
    column {
      name = "memory_total"
      type = "int"
    }
    column {
      name = "tags"
      type = "dynamic"
    }
    column {
      name = "unix_time"
      type = "long"
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
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixCmd_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "action"
      type = "string"
    }
    column {
      name = "args"
      type = "string"
    }
    column {
      name = "controller_ip"
      type = "string"
    }
    column {
      name = "gw_hostname"
      type = "string"
    }
    column {
      name = "ls_timestamp"
      type = "string"
    }
    column {
      name = "reason"
      type = "string"
    }
    column {
      name = "result"
      type = "string"
    }
    column {
      name = "tags"
      type = "dynamic"
    }
    column {
      name = "unix_time"
      type = "long"
    }
    column {
      name = "username"
      type = "string"
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
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixTunnelStatus_CL"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "dst_gw"
      type = "string"
    }
    column {
      name = "ls_timestamp"
      type = "string"
    }
    column {
      name = "new_state"
      type = "string"
    }
    column {
      name = "old_state"
      type = "string"
    }
    column {
      name = "src_gw"
      type = "string"
    }
    column {
      name = "tags"
      type = "dynamic"
    }
    column {
      name = "unix_time"
      type = "long"
    }
  }
}

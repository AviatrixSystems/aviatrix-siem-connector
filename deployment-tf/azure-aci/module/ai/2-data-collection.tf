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
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixNetworkSession_CL"
    # ASIM common fields
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "EventVendor"
      type = "string"
    }
    column {
      name = "EventProduct"
      type = "string"
    }
    column {
      name = "EventSchema"
      type = "string"
    }
    column {
      name = "EventSchemaVersion"
      type = "string"
    }
    column {
      name = "EventType"
      type = "string"
    }
    column {
      name = "EventCount"
      type = "int"
    }
    column {
      name = "EventResult"
      type = "string"
    }
    column {
      name = "EventSeverity"
      type = "string"
    }
    column {
      name = "EventStartTime"
      type = "datetime"
    }
    column {
      name = "EventEndTime"
      type = "datetime"
    }
    column {
      name = "EventSubType"
      type = "string"
    }
    # ASIM action/device fields
    column {
      name = "DvcAction"
      type = "string"
    }
    column {
      name = "DvcOriginalAction"
      type = "string"
    }
    column {
      name = "DvcHostname"
      type = "string"
    }
    column {
      name = "DvcIpAddr"
      type = "string"
    }
    # ASIM network fields
    column {
      name = "SrcIpAddr"
      type = "string"
    }
    column {
      name = "DstIpAddr"
      type = "string"
    }
    column {
      name = "SrcPortNumber"
      type = "int"
    }
    column {
      name = "DstPortNumber"
      type = "int"
    }
    column {
      name = "SrcMacAddr"
      type = "string"
    }
    column {
      name = "DstMacAddr"
      type = "string"
    }
    column {
      name = "NetworkProtocol"
      type = "string"
    }
    column {
      name = "NetworkRuleName"
      type = "string"
    }
    column {
      name = "NetworkSessionId"
      type = "string"
    }
    column {
      name = "NetworkBytes"
      type = "long"
    }
    column {
      name = "NetworkDuration"
      type = "int"
    }
    column {
      name = "NetworkPackets"
      type = "long"
    }
    # Aviatrix-specific fields
    column {
      name = "enforced"
      type = "boolean"
    }
    column {
      name = "ip_size"
      type = "int"
    }
    column {
      name = "session_event"
      type = "int"
    }
    column {
      name = "session_end_reason"
      type = "int"
    }
    column {
      name = "session_pkt_cnt"
      type = "long"
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
      name = "session_id"
      type = "long"
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
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixWebSession_CL"
    # ASIM common fields
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "EventVendor"
      type = "string"
    }
    column {
      name = "EventProduct"
      type = "string"
    }
    column {
      name = "EventSchema"
      type = "string"
    }
    column {
      name = "EventSchemaVersion"
      type = "string"
    }
    column {
      name = "EventType"
      type = "string"
    }
    column {
      name = "EventCount"
      type = "int"
    }
    column {
      name = "EventResult"
      type = "string"
    }
    column {
      name = "EventSeverity"
      type = "string"
    }
    column {
      name = "EventStartTime"
      type = "datetime"
    }
    column {
      name = "EventEndTime"
      type = "datetime"
    }
    # ASIM action/device fields
    column {
      name = "DvcAction"
      type = "string"
    }
    column {
      name = "DvcOriginalAction"
      type = "string"
    }
    column {
      name = "DvcHostname"
      type = "string"
    }
    column {
      name = "DvcIpAddr"
      type = "string"
    }
    # ASIM network fields
    column {
      name = "SrcIpAddr"
      type = "string"
    }
    column {
      name = "DstIpAddr"
      type = "string"
    }
    column {
      name = "SrcPortNumber"
      type = "int"
    }
    column {
      name = "DstPortNumber"
      type = "int"
    }
    column {
      name = "NetworkProtocol"
      type = "string"
    }
    column {
      name = "NetworkRuleName"
      type = "string"
    }
    # ASIM web session fields
    column {
      name = "DstFqdn"
      type = "string"
    }
    column {
      name = "DstHostname"
      type = "string"
    }
    column {
      name = "Url"
      type = "string"
    }
    # Aviatrix-specific fields
    column {
      name = "enforced"
      type = "boolean"
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
      name = "mitm_decrypted_by"
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
    transform_kql = "source"
  }

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace.id
      name                  = "loganalytics-destination"
    }
  }

  stream_declaration {
    stream_name = "Custom-AviatrixIDS_CL"
    # ASIM common fields
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "EventVendor"
      type = "string"
    }
    column {
      name = "EventProduct"
      type = "string"
    }
    column {
      name = "EventSchema"
      type = "string"
    }
    column {
      name = "EventSchemaVersion"
      type = "string"
    }
    column {
      name = "EventType"
      type = "string"
    }
    column {
      name = "EventCount"
      type = "int"
    }
    column {
      name = "EventResult"
      type = "string"
    }
    column {
      name = "EventSeverity"
      type = "string"
    }
    column {
      name = "EventStartTime"
      type = "datetime"
    }
    column {
      name = "EventEndTime"
      type = "datetime"
    }
    # ASIM action fields
    column {
      name = "DvcAction"
      type = "string"
    }
    column {
      name = "DvcOriginalAction"
      type = "string"
    }
    column {
      name = "DvcInboundInterface"
      type = "string"
    }
    # ASIM network fields
    column {
      name = "SrcIpAddr"
      type = "string"
    }
    column {
      name = "DstIpAddr"
      type = "string"
    }
    column {
      name = "SrcPortNumber"
      type = "int"
    }
    column {
      name = "DstPortNumber"
      type = "int"
    }
    column {
      name = "NetworkProtocol"
      type = "string"
    }
    column {
      name = "NetworkApplicationProtocol"
      type = "string"
    }
    column {
      name = "NetworkRuleName"
      type = "string"
    }
    column {
      name = "NetworkRuleNumber"
      type = "int"
    }
    column {
      name = "NetworkSessionId"
      type = "string"
    }
    column {
      name = "SrcBytes"
      type = "long"
    }
    column {
      name = "DstBytes"
      type = "long"
    }
    column {
      name = "SrcPackets"
      type = "long"
    }
    column {
      name = "DstPackets"
      type = "long"
    }
    # ASIM threat fields
    column {
      name = "ThreatName"
      type = "string"
    }
    column {
      name = "ThreatId"
      type = "string"
    }
    column {
      name = "ThreatCategory"
      type = "string"
    }
    column {
      name = "ThreatRiskLevel"
      type = "int"
    }
    column {
      name = "ThreatOriginalRiskLevel"
      type = "string"
    }
    # Suricata-native / Aviatrix-specific fields
    column {
      name = "alert"
      type = "dynamic"
    }
    column {
      name = "flow"
      type = "dynamic"
    }
    column {
      name = "http"
      type = "dynamic"
    }
    column {
      name = "tls"
      type = "dynamic"
    }
    column {
      name = "dns"
      type = "dynamic"
    }
    column {
      name = "tcp"
      type = "dynamic"
    }
    column {
      name = "event_type"
      type = "string"
    }
    column {
      name = "app_proto"
      type = "string"
    }
    column {
      name = "flow_id"
      type = "long"
    }
    column {
      name = "direction"
      type = "string"
    }
    column {
      name = "pkt_src"
      type = "string"
    }
    column {
      name = "tx_id"
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
      name = "timestamp"
      type = "string"
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

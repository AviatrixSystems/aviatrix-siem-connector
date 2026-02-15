# Custom Log Analytics Tables (managed via azapi)
# These tables must exist BEFORE the DCRs that reference them.
#
# Security tables use ASIM-normalized schemas:
#   AviatrixNetworkSession_CL - L4 microseg (ASIM NetworkSession)
#   AviatrixWebSession_CL     - L7 MITM/DCF (ASIM WebSession)
#   AviatrixIDS_CL            - Suricata IDS (ASIM NetworkSession, EventType=IDS)
#
# For existing deployments migrating from old table names, import into state:
#   terraform import 'module.deployment.azapi_resource.table_netsession' \
#     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>/tables/AviatrixNetworkSession_CL'
#   terraform import 'module.deployment.azapi_resource.table_websession' \
#     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>/tables/AviatrixWebSession_CL'
#   terraform import 'module.deployment.azapi_resource.table_ids' \
#     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>/tables/AviatrixIDS_CL'

resource "azapi_resource" "table_netsession" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixNetworkSession_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixNetworkSession_CL"
        columns = [
          # ASIM common fields
          { name = "TimeGenerated", type = "datetime" },
          { name = "EventVendor", type = "string" },
          { name = "EventProduct", type = "string" },
          { name = "EventSchema", type = "string" },
          { name = "EventSchemaVersion", type = "string" },
          { name = "EventType", type = "string" },
          { name = "EventCount", type = "int" },
          { name = "EventResult", type = "string" },
          { name = "EventSeverity", type = "string" },
          { name = "EventStartTime", type = "datetime" },
          { name = "EventEndTime", type = "datetime" },
          { name = "EventSubType", type = "string" },
          # ASIM action fields
          { name = "DvcAction", type = "string" },
          { name = "DvcOriginalAction", type = "string" },
          { name = "DvcHostname", type = "string" },
          { name = "DvcIpAddr", type = "string" },
          # ASIM network fields
          { name = "SrcIpAddr", type = "string" },
          { name = "DstIpAddr", type = "string" },
          { name = "SrcPortNumber", type = "int" },
          { name = "DstPortNumber", type = "int" },
          { name = "SrcMacAddr", type = "string" },
          { name = "DstMacAddr", type = "string" },
          { name = "NetworkProtocol", type = "string" },
          { name = "NetworkRuleName", type = "string" },
          { name = "NetworkSessionId", type = "string" },
          { name = "NetworkBytes", type = "long" },
          { name = "NetworkDuration", type = "int" },
          { name = "NetworkPackets", type = "long" },
          # Aviatrix-specific fields preserved
          { name = "enforced", type = "boolean" },
          { name = "ip_size", type = "int" },
          { name = "session_event", type = "int" },
          { name = "session_end_reason", type = "int" },
          { name = "session_pkt_cnt", type = "long" },
          { name = "session_byte_cnt", type = "long" },
          { name = "session_dur", type = "long" },
          { name = "session_id", type = "long" },
          { name = "tags", type = "dynamic" },
          { name = "unix_time", type = "long" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_websession" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixWebSession_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixWebSession_CL"
        columns = [
          # ASIM common fields
          { name = "TimeGenerated", type = "datetime" },
          { name = "EventVendor", type = "string" },
          { name = "EventProduct", type = "string" },
          { name = "EventSchema", type = "string" },
          { name = "EventSchemaVersion", type = "string" },
          { name = "EventType", type = "string" },
          { name = "EventCount", type = "int" },
          { name = "EventResult", type = "string" },
          { name = "EventSeverity", type = "string" },
          { name = "EventStartTime", type = "datetime" },
          { name = "EventEndTime", type = "datetime" },
          # ASIM action fields
          { name = "DvcAction", type = "string" },
          { name = "DvcOriginalAction", type = "string" },
          { name = "DvcHostname", type = "string" },
          { name = "DvcIpAddr", type = "string" },
          # ASIM network fields
          { name = "SrcIpAddr", type = "string" },
          { name = "DstIpAddr", type = "string" },
          { name = "SrcPortNumber", type = "int" },
          { name = "DstPortNumber", type = "int" },
          { name = "NetworkProtocol", type = "string" },
          { name = "NetworkRuleName", type = "string" },
          # ASIM web session fields
          { name = "DstFqdn", type = "string" },
          { name = "DstHostname", type = "string" },
          { name = "Url", type = "string" },
          # Aviatrix-specific fields preserved
          { name = "enforced", type = "boolean" },
          { name = "mitm_sni_hostname", type = "string" },
          { name = "mitm_url_parts", type = "string" },
          { name = "mitm_decrypted_by", type = "string" },
          { name = "tags", type = "dynamic" },
          { name = "unix_time", type = "long" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_ids" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixIDS_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixIDS_CL"
        columns = [
          # ASIM common fields
          { name = "TimeGenerated", type = "datetime" },
          { name = "EventVendor", type = "string" },
          { name = "EventProduct", type = "string" },
          { name = "EventSchema", type = "string" },
          { name = "EventSchemaVersion", type = "string" },
          { name = "EventType", type = "string" },
          { name = "EventCount", type = "int" },
          { name = "EventResult", type = "string" },
          { name = "EventSeverity", type = "string" },
          { name = "EventStartTime", type = "datetime" },
          { name = "EventEndTime", type = "datetime" },
          # ASIM action fields
          { name = "DvcAction", type = "string" },
          { name = "DvcOriginalAction", type = "string" },
          { name = "DvcInboundInterface", type = "string" },
          # ASIM network fields
          { name = "SrcIpAddr", type = "string" },
          { name = "DstIpAddr", type = "string" },
          { name = "SrcPortNumber", type = "int" },
          { name = "DstPortNumber", type = "int" },
          { name = "NetworkProtocol", type = "string" },
          { name = "NetworkApplicationProtocol", type = "string" },
          { name = "NetworkRuleName", type = "string" },
          { name = "NetworkRuleNumber", type = "int" },
          { name = "NetworkSessionId", type = "string" },
          { name = "SrcBytes", type = "long" },
          { name = "DstBytes", type = "long" },
          { name = "SrcPackets", type = "long" },
          { name = "DstPackets", type = "long" },
          # ASIM threat fields
          { name = "ThreatName", type = "string" },
          { name = "ThreatId", type = "string" },
          { name = "ThreatCategory", type = "string" },
          { name = "ThreatRiskLevel", type = "int" },
          { name = "ThreatOriginalRiskLevel", type = "string" },
          # Suricata-native / Aviatrix-specific fields preserved
          { name = "alert", type = "dynamic" },
          { name = "flow", type = "dynamic" },
          { name = "http", type = "dynamic" },
          { name = "tls", type = "dynamic" },
          { name = "dns", type = "dynamic" },
          { name = "tcp", type = "dynamic" },
          { name = "event_type", type = "string" },
          { name = "app_proto", type = "string" },
          { name = "flow_id", type = "long" },
          { name = "direction", type = "string" },
          { name = "pkt_src", type = "string" },
          { name = "tx_id", type = "int" },
          { name = "tags", type = "dynamic" },
          { name = "unix_time", type = "long" },
          { name = "timestamp", type = "string" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_gw_net_stats" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixGwNetStats_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixGwNetStats_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "alias", type = "string" },
          { name = "bw_in_limit_exceeded", type = "int" },
          { name = "bw_out_limit_exceeded", type = "int" },
          { name = "conntrack_allowance_available", type = "int" },
          { name = "conntrack_count", type = "int" },
          { name = "conntrack_limit_exceeded", type = "int" },
          { name = "conntrack_usage_rate", type = "int" },
          { name = "gateway", type = "string" },
          { name = "interface", type = "string" },
          { name = "linklocal_limit_exceeded", type = "int" },
          { name = "ls_timestamp", type = "string" },
          { name = "pps_limit_exceeded", type = "int" },
          { name = "private_ip", type = "string" },
          { name = "public_ip", type = "string" },
          { name = "tags", type = "dynamic" },
          { name = "total_rx_cum", type = "string" },
          { name = "total_rx_rate", type = "int" },
          { name = "total_rx_tx_cum", type = "string" },
          { name = "total_rx_tx_rate", type = "int" },
          { name = "total_tx_cum", type = "string" },
          { name = "total_tx_rate", type = "int" },
          { name = "unix_time", type = "long" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_gw_sys_stats" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixGwSysStats_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixGwSysStats_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "alias", type = "string" },
          { name = "cpu_aggregate_busy_avg", type = "int" },
          { name = "cpu_aggregate_busy_max", type = "int" },
          { name = "cpu_aggregate_busy_min", type = "int" },
          { name = "cpu_busy", type = "real" },
          { name = "cpu_core_count", type = "int" },
          { name = "cpu_cores_parsed", type = "dynamic" },
          { name = "cpu_idle", type = "real" },
          { name = "disk_free", type = "int" },
          { name = "disk_total", type = "int" },
          { name = "gateway", type = "string" },
          { name = "ls_timestamp", type = "string" },
          { name = "memory_available", type = "int" },
          { name = "memory_free", type = "int" },
          { name = "memory_total", type = "int" },
          { name = "tags", type = "dynamic" },
          { name = "unix_time", type = "long" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_cmd" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixCmd_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixCmd_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "action", type = "string" },
          { name = "args", type = "string" },
          { name = "controller_ip", type = "string" },
          { name = "gw_hostname", type = "string" },
          { name = "ls_timestamp", type = "string" },
          { name = "reason", type = "string" },
          { name = "result", type = "string" },
          { name = "tags", type = "dynamic" },
          { name = "unix_time", type = "long" },
          { name = "username", type = "string" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_tunnel_status" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixTunnelStatus_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixTunnelStatus_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "dst_gw", type = "string" },
          { name = "ls_timestamp", type = "string" },
          { name = "new_state", type = "string" },
          { name = "old_state", type = "string" },
          { name = "src_gw", type = "string" },
          { name = "tags", type = "dynamic" },
          { name = "unix_time", type = "long" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

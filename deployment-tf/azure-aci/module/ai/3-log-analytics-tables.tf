# Custom Log Analytics Tables (managed via azapi)
# These tables must exist BEFORE the DCRs that reference them.
#
# For existing deployments, import tables into state before first apply:
#   terraform import 'module.deployment.azapi_resource.table_microseg' \
#     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>/tables/AviatrixMicroseg_CL'
#   terraform import 'module.deployment.azapi_resource.table_suricata' \
#     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>/tables/AviatrixSuricata_CL'

resource "azapi_resource" "table_microseg" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixMicroseg_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixMicroseg_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "action", type = "string" },
          { name = "dst_ip", type = "string" },
          { name = "dst_mac", type = "string" },
          { name = "dst_port", type = "int" },
          { name = "enforced", type = "boolean" },
          { name = "gw_hostname", type = "string" },
          { name = "gw_ip", type = "string" },
          { name = "ip_size", type = "int" },
          { name = "ls_timestamp", type = "string" },
          { name = "mitm_decrypted_by", type = "string" },
          { name = "mitm_sni_hostname", type = "string" },
          { name = "mitm_url_parts", type = "string" },
          { name = "proto", type = "string" },
          { name = "session_byte_cnt", type = "long" },
          { name = "session_dur", type = "long" },
          { name = "session_end_reason", type = "int" },
          { name = "session_event", type = "int" },
          { name = "session_id", type = "long" },
          { name = "session_pkt_cnt", type = "long" },
          { name = "src_ip", type = "string" },
          { name = "src_mac", type = "string" },
          { name = "src_port", type = "int" },
          { name = "tags", type = "dynamic" },
          { name = "unix_time", type = "long" },
          { name = "uuid", type = "string" },
        ]
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_suricata" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixSuricata_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name = "AviatrixSuricata_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "Computer", type = "string" },
          { name = "alert", type = "dynamic" },
          { name = "app_proto", type = "string" },
          { name = "dest_ip", type = "string" },
          { name = "dest_port", type = "int" },
          { name = "event_type", type = "string" },
          { name = "files", type = "dynamic" },
          { name = "flow", type = "dynamic" },
          { name = "flow_id", type = "long" },
          { name = "http", type = "dynamic" },
          { name = "in_iface", type = "string" },
          { name = "ls_timestamp", type = "string" },
          { name = "ls_version", type = "string" },
          { name = "proto", type = "string" },
          { name = "src_ip", type = "string" },
          { name = "src_port", type = "int" },
          { name = "tags", type = "dynamic" },
          { name = "timestamp", type = "string" },
          { name = "tx_id", type = "int" },
          { name = "unix_time", type = "long" },
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

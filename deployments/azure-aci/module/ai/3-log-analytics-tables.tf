# Custom Log Analytics Tables (managed via azapi)
# These tables must exist BEFORE the DCRs that reference them.
# Column lists live in 4-table-schemas.tf (shared with the DCR stream declarations).
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
        name    = "AviatrixNetworkSession_CL"
        columns = local.table_schemas.netsession
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
        name    = "AviatrixWebSession_CL"
        columns = local.table_schemas.websession
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
        name    = "AviatrixIDS_CL"
        columns = local.table_schemas.ids
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
        name    = "AviatrixGwNetStats_CL"
        columns = local.table_schemas.gw_net_stats
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
        name    = "AviatrixGwSysStats_CL"
        columns = local.table_schemas.gw_sys_stats
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

resource "azapi_resource" "table_vpn_session" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "AviatrixVPNSession_CL"
  parent_id = var.log_analytics_workspace.id

  body = {
    properties = {
      schema = {
        name    = "AviatrixVPNSession_CL"
        columns = local.table_schemas.vpn_session
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
        name    = "AviatrixCmd_CL"
        columns = local.table_schemas.cmd
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
        name    = "AviatrixTunnelStatus_CL"
        columns = local.table_schemas.tunnel_status
      }
      retentionInDays      = 30
      totalRetentionInDays = 30
    }
  }
}

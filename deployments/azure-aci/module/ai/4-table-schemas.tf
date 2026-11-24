# Single source of truth for the custom table / DCR stream schemas.
#
# Each list is used twice:
#   - 3-log-analytics-tables.tf  -> azapi table body (schema.columns)
#   - 2-data-collection.tf       -> DCR stream_declaration (dynamic "column")
#
# DCR stream declarations are derived from these lists (stream_schemas below):
# int/long/real/boolean columns are declared "dynamic" and cast in the DCR
# transform. A typed stream column stores null when the JSON value is a string
# ("1267" into an int column), and Logstash sends many numbers as strings.
# Tested against Log Analytics 2026-11: dynamic + toint()/tolong()/toreal()/
# tobool() stores both JSON numbers and numeric strings; a decimal string into
# an int and a value above the long maximum still store null.
#
# The DCR silently drops any property that is not declared here, so every field
# that logstash-configs/outputs/azure-log-ingestion/output.conf sends (and that
# should land in Log Analytics) must be listed. Add new columns at the END of a
# list to keep plans small; column order has no effect on ingestion.

locals {
  table_schemas = {
    netsession = [
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
      # Added 2026-11: session end reason (EventOriginalResultDetails is read by the ASIM parser)
      { name = "EventOriginalResultDetails", type = "string" },
      { name = "session_end_reason_text", type = "string" },
      # Added 2026-11: 10.1+ microseg fields and the session event label
      { name = "session_start", type = "string" },
      { name = "egress_path", type = "string" },
      { name = "session_event_type", type = "string" },
    ]
    websession = [
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
      # Added 2026-11: ASIM fields set by output.conf mitm-asim-mapping
      { name = "EventSubType", type = "string" },
      { name = "NetworkSessionId", type = "string" },
      { name = "SrcBytes", type = "long" },
      { name = "DstBytes", type = "long" },
      { name = "ThreatId", type = "string" },
      # Added 2026-11: raw L7 fields from filters/11-l7-dcf.conf
      { name = "mitm_reason", type = "string" },
      { name = "mitm_session_id", type = "string" },
      { name = "mitm_session_stage", type = "string" },
      { name = "mitm_stage", type = "string" },
      { name = "mitm_ids", type = "string" },
      { name = "mitm_priority", type = "string" },
      { name = "mitm_sid", type = "string" },
      { name = "mitm_message", type = "string" },
      { name = "mitm_request_bytes", type = "string" },
      { name = "mitm_response_bytes", type = "string" },
      { name = "mitm_session_time", type = "string" },
    ]
    ids = [
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
      # Added 2026-11: gateway that raised the alert (from gw_hostname)
      { name = "DvcHostname", type = "string" },
    ]
    gw_net_stats = [
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
      # Added 2026-11, set by the DCR transform (dcr_transform_prefix) from the
      # columns above: the exact usage rate (conntrack_usage_rate is an int and
      # truncates it) and the rates in bits/s (the int rate columns store null
      # above 2^31-1, i.e. ~2.1 Gbit/s).
      { name = "conntrack_usage_pct", type = "real" },
      { name = "total_rx_bps", type = "real" },
      { name = "total_tx_bps", type = "real" },
      { name = "total_rx_tx_bps", type = "real" },
    ]
    gw_sys_stats = [
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
    cmd = [
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
      # Added 2026-11: V2.5 API method, client IP and Host header
      { name = "http_method", type = "string" },
      { name = "client_ip", type = "string" },
      { name = "api_host", type = "string" },
    ]
    tunnel_status = [
      { name = "TimeGenerated", type = "datetime" },
      { name = "dst_gw", type = "string" },
      { name = "ls_timestamp", type = "string" },
      { name = "new_state", type = "string" },
      { name = "old_state", type = "string" },
      { name = "src_gw", type = "string" },
      { name = "tags", type = "dynamic" },
      { name = "unix_time", type = "long" },
      { name = "reporting_gw", type = "string" },
      { name = "src_intf", type = "string" },
      { name = "dst_intf", type = "string" },
    ]
    vpn_session = [
      { name = "TimeGenerated", type = "datetime" },
      { name = "vpn_user", type = "string" },
      { name = "vpn_status", type = "string" },
      { name = "vpn_gateway", type = "string" },
      { name = "vpn_gateway_ip", type = "string" },
      { name = "vpn_virtual_ip", type = "string" },
      { name = "vpn_public_ip", type = "string" },
      { name = "vpn_login", type = "string" },
      { name = "vpn_logout", type = "string" },
      { name = "vpn_duration", type = "string" },
      { name = "vpn_rx_bytes", type = "string" },
      { name = "vpn_tx_bytes", type = "string" },
      { name = "vpn_client_platform", type = "string" },
      { name = "vpn_client_version", type = "string" },
      { name = "tags", type = "dynamic" },
      { name = "unix_time", type = "long" },
    ]
  }

  # --- Derived: DCR stream declarations and transforms (2-data-collection.tf) ---
  dcr_cast = {
    int     = "toint(toreal(%s))" # toreal first so "12.0" and 12.0 also cast
    long    = "tolong(%s)"        # no toreal: it would lose precision above 2^53
    real    = "toreal(%s)"
    boolean = "tobool(%s)"
  }

  stream_schemas = {
    for table, cols in local.table_schemas : table => [
      for c in cols : { name = c.name, type = contains(keys(local.dcr_cast), c.type) ? "dynamic" : c.type }
    ]
  }

  # Extra KQL that runs before the casts, per table. Columns it sets must also be
  # in the table list above (they are cast like any other column).
  dcr_transform_prefix = {
    gw_net_stats = "extend conntrack_usage_pct = conntrack_usage_rate, total_rx_bps = total_rx_rate, total_tx_bps = total_tx_rate, total_rx_tx_bps = total_rx_tx_rate"
  }

  dcr_casts = {
    for table, cols in local.table_schemas : table => [
      for c in cols : format("%s = %s", c.name, format(local.dcr_cast[c.type], c.name))
      if contains(keys(local.dcr_cast), c.type)
    ]
  }

  dcr_transform_kql = {
    for table, casts in local.dcr_casts : table => join(" | ", compact([
      "source",
      lookup(local.dcr_transform_prefix, table, ""),
      length(casts) > 0 ? "extend ${join(", ", casts)}" : "",
    ]))
  }
}

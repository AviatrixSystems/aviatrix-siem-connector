# Design: Surface MITM Fields + Add VPNSession Filter

**Date:** 2026-03-02
**Scope:** Two changes to the Logstash filter pipeline

---

## Change 1: Surface Missing MITM/L7 DCF Fields

### Problem

The L7 DCF filter (`11-l7-dcf.conf`) parses the full `traffic_server` JSON into `[@metadata][payload]` but only maps 9 fields to root level. Security-critical fields like `reason`, `sid`, `session_id`, and byte counts are parsed but discarded — invisible to outputs.

### Solution

Add `mutate add_field` and conditional blocks in `11-l7-dcf.conf` to surface these fields:

**Always-present fields** (add to existing `mutate add_field` block):

| JSON key | Root field | Description |
|---|---|---|
| `reason` | `mitm_reason` | POLICY, IPS_POLICY_DENY, IDS_POLICY_ALERT, TLS_PROFILE, etc. |
| `session_id` | `mitm_session_id` | UUID for session correlation |
| `session_stage` | `mitm_session_stage` | start, tls_check, end |
| `stage` | `mitm_stage` | SNI, ORIGIN_CERT_VALIDATE, txn |
| `ids` | `mitm_ids` | Whether IDS inspection is active |
| `priority` | `mitm_priority` | LOG_ALERT, LOG_WARNING |

**Conditional fields** (using existing `if [@metadata][payload][field]` pattern):

| JSON key | Root field | Present when |
|---|---|---|
| `request_bytes` | `mitm_request_bytes` | Session end |
| `response_bytes` | `mitm_response_bytes` | Session end |
| `sid` | `mitm_sid` | IDS/IPS events |
| `session_time` | `mitm_session_time` | Not on session start |
| `message` | `mitm_message` | TLS validation events |

All fields use the `mitm_` prefix for consistency with existing `mitm_sni_hostname`, `mitm_url_parts`, `mitm_decrypted_by`.

### Downstream Updates

- **Azure ASIM mapping**: Add mappings for new fields in `azure-log-ingestion/output.conf`:
  - `mitm_request_bytes` / `mitm_response_bytes` → `SrcBytes` / `DstBytes`
  - `mitm_reason` → useful for `EventSubType` or similar
  - `mitm_sid` → threat correlation
- **Splunk**: Already sends full `[@metadata][payload]` as the event — new root fields are additive.
- **Other outputs**: Get new fields automatically via `format => "json"`.

### Test Samples

Existing test samples (11 MITM lines) already cover all `reason` variants. No new samples needed — just verify the new fields appear in output.

---

## Change 2: Add AviatrixVPNSession Filter

### Problem

VPN session connect/disconnect logs are documented and actively emitted but have no filter. They arrive as raw syslog and are silently dropped or pass through unstructured.

### Solution

New filter file `18-vpn-session.conf`:

```ruby
filter {
    if [type] == "syslog" and "AviatrixVPNSession" in [message] {
        grok {
            id => "vpn-session"
            patterns_dir => ["/usr/share/logstash/patterns"]
            add_tag => ["vpn_session"]
            tag_on_failure => []
            match => {
                "message" => [
                    "%{SYSLOG_TIMESTAMP:date}.*AviatrixVPNSession: User=%{DATA:vpn_user}, Status=%{WORD:vpn_status}, Gateway=%{DATA:vpn_gateway}, GatewayIP=%{IP:vpn_gateway_ip}, VPNVirtualIP=%{DATA:vpn_virtual_ip}, PublicIP=%{DATA:vpn_public_ip}, Login=%{DATA:vpn_login}, Logout=%{DATA:vpn_logout}, Duration=%{DATA:vpn_duration}, RXbytes=%{DATA:vpn_rx_bytes}, TXbytes=%{DATA:vpn_tx_bytes}, VPNClientPlatform=%{DATA:vpn_client_platform}, VPNClientVersion=%{GREEDYDATA:vpn_client_version}"
                ]
            }
        }
    }
}
```

### Fields

All prefixed `vpn_` for namespacing:

| Field | Example (connect) | Example (disconnect) |
|---|---|---|
| `vpn_user` | `demo` | `demo` |
| `vpn_status` | `active` | `disconnected` |
| `vpn_gateway` | `vpn-gw-1` | `vpn-gw-1` |
| `vpn_gateway_ip` | `52.52.76.149` | `52.52.76.149` |
| `vpn_virtual_ip` | `192.168.0.6` | `192.168.0.6` |
| `vpn_public_ip` | `N/A` or IP | `N/A` or IP |
| `vpn_login` | `2024-08-17 22:07:38` | `2024-08-17 22:07:38` |
| `vpn_logout` | `N/A` | `2024-08-17 22:26:37` |
| `vpn_duration` | `N/A` | `0:0:18:59` |
| `vpn_rx_bytes` | `N/A` | `2.1 MB` |
| `vpn_tx_bytes` | `N/A` | `9.03 MB` |
| `vpn_client_platform` | `Windows` | `Windows` |
| `vpn_client_version` | `2.14.14` | `2.14.14` |

### Profile & Tag

- **Tag**: `vpn_session`
- **LOG_PROFILE**: `security` (audit/compliance use case)

### Output Blocks

Add to each output type:
- **Splunk**: sourcetype `aviatrix:vpn:session`, source `avx-vpn-session`
- **Azure**: Custom table `AviatrixVPNSession_CL` (no ASIM normalization — no standard ASIM schema for VPN sessions)
- **Webhook-test**: Standard JSON output
- **Other outputs**: As needed

### Test Samples

Add 2 lines to `test-tools/sample-logs/test-samples.log`:
1. Connect event (`Status=active`, N/A fields)
2. Disconnect event (`Status=disconnected`, filled duration/bytes)

### CONTRIBUTING.md Update

Add `vpn_session` → `security` to the Log Type to Profile Mapping table.

# MITM Field Surfacing + VPNSession Filter — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Surface 11 missing fields from L7/MITM JSON payload to root level, and add a new AviatrixVPNSession filter for VPN connect/disconnect log parsing.

**Architecture:** Both changes follow existing patterns — MITM adds `mutate add_field` entries in `11-l7-dcf.conf`; VPNSession adds a new `18-vpn-session.conf` filter plus output blocks in each destination config. All changes follow the tag-based routing and LOG_PROFILE gating conventions.

**Tech Stack:** Logstash filter/output configs (Grok, JSON, mutate, Ruby), Logstash patterns

---

## Task 1: Surface MITM Always-Present Fields

**Files:**
- Modify: `logstash-configs/filters/11-l7-dcf.conf` (lines 42-55, the `mutate add_field` block)

**Step 1: Add 6 always-present fields to the existing `mutate add_field` block**

In `11-l7-dcf.conf`, find the `mutate` block with id `mitm-map-to-microseg` (line 42-55). Add these 6 fields to the existing `add_field` hash:

```ruby
                    "mitm_reason" => "%{[@metadata][payload][reason]}"
                    "mitm_session_id" => "%{[@metadata][payload][session_id]}"
                    "mitm_session_stage" => "%{[@metadata][payload][session_stage]}"
                    "mitm_stage" => "%{[@metadata][payload][stage]}"
                    "mitm_ids" => "%{[@metadata][payload][ids]}"
                    "mitm_priority" => "%{[@metadata][payload][priority]}"
```

These go right after the existing `"mitm_sni_hostname"` line inside the same `add_field` block.

**Step 2: Commit**

```bash
git add logstash-configs/filters/11-l7-dcf.conf
git commit -m "Add always-present MITM fields to root level

Surface reason, session_id, session_stage, stage, ids, and priority
from [@metadata][payload] to root-level mitm_* fields."
```

---

## Task 2: Surface MITM Conditional Fields

**Files:**
- Modify: `logstash-configs/filters/11-l7-dcf.conf` (after line 85, alongside existing conditional blocks for `url` and `decrypted_by`)

**Step 1: Add conditional field blocks**

After the existing `decrypted_by` conditional block (ends around line 85), add these 5 conditional blocks following the exact same pattern:

```ruby
            # Add request_bytes if present (session end)
            if [@metadata][payload][request_bytes] {
                mutate {
                    id => "mitm-request-bytes"
                    add_field => {
                        "mitm_request_bytes" => "%{[@metadata][payload][request_bytes]}"
                    }
                }
            }

            # Add response_bytes if present (session end)
            if [@metadata][payload][response_bytes] {
                mutate {
                    id => "mitm-response-bytes"
                    add_field => {
                        "mitm_response_bytes" => "%{[@metadata][payload][response_bytes]}"
                    }
                }
            }

            # Add sid if present (IDS/IPS events)
            if [@metadata][payload][sid] {
                mutate {
                    id => "mitm-sid"
                    add_field => {
                        "mitm_sid" => "%{[@metadata][payload][sid]}"
                    }
                }
            }

            # Add session_time if present (not on session start)
            if [@metadata][payload][session_time] {
                mutate {
                    id => "mitm-session-time"
                    add_field => {
                        "mitm_session_time" => "%{[@metadata][payload][session_time]}"
                    }
                }
            }

            # Add message if present (TLS validation events)
            if [@metadata][payload][message] {
                mutate {
                    id => "mitm-tls-message"
                    add_field => {
                        "mitm_message" => "%{[@metadata][payload][message]}"
                    }
                }
            }
```

**Step 2: Commit**

```bash
git add logstash-configs/filters/11-l7-dcf.conf
git commit -m "Add conditional MITM fields to root level

Surface request_bytes, response_bytes, sid, session_time, and message
from [@metadata][payload] when present."
```

---

## Task 3: Update Azure ASIM Mapping for New MITM Fields

**Files:**
- Modify: `logstash-configs/outputs/azure-log-ingestion/output.conf` (the `mitm-asim-mapping` Ruby block, around lines 286-330)

**Step 1: Add ASIM field mappings for new MITM fields**

In the Ruby block with id `mitm-asim-mapping`, add these lines after the existing `DvcIpAddr` mapping (around line 305):

```ruby
                # Byte counts (ASIM WebSession)
                event.set('SrcBytes', event.get('mitm_request_bytes').to_i) if event.get('mitm_request_bytes')
                event.set('DstBytes', event.get('mitm_response_bytes').to_i) if event.get('mitm_response_bytes')

                # Session correlation
                event.set('NetworkSessionId', event.get('mitm_session_id')) if event.get('mitm_session_id')

                # Suricata signature ID for IDS/IPS events
                event.set('ThreatId', event.get('mitm_sid')) if event.get('mitm_sid')

                # Event sub-type from reason
                event.set('EventSubType', event.get('mitm_reason')) if event.get('mitm_reason')
```

**Step 2: Commit**

```bash
git add logstash-configs/outputs/azure-log-ingestion/output.conf
git commit -m "Map new MITM fields to ASIM WebSession schema

Add SrcBytes, DstBytes, NetworkSessionId, ThreatId, and EventSubType
from newly surfaced mitm_* fields."
```

---

## Task 4: Update Dynatrace MITM Log Builder for New Fields

**Files:**
- Modify: `logstash-configs/outputs/dynatrace/output.conf` (the `dynatrace-build-mitm-log` Ruby block, around lines 400-452)

**Step 1: Add new fields to the Dynatrace log payload**

In the Ruby block with id `dynatrace-build-mitm-log`, after the existing `decrypted_by` resolution (around line 419), add:

```ruby
                reason = resolve.call(event.get("mitm_reason"))
                sid = resolve.call(event.get("mitm_sid"))
                session_id = resolve.call(event.get("mitm_session_id"))
                request_bytes = event.get("mitm_request_bytes")
                response_bytes = event.get("mitm_response_bytes")
```

Then after the existing conditional `log_event` additions (around line 449), add:

```ruby
                log_event["aviatrix.dcf.reason"] = reason unless reason.empty?
                log_event["aviatrix.dcf.session_id"] = session_id unless session_id.empty?
                log_event["aviatrix.dcf.sid"] = sid unless sid.empty?
                log_event["aviatrix.dcf.request_bytes"] = request_bytes.to_i if request_bytes
                log_event["aviatrix.dcf.response_bytes"] = response_bytes.to_i if response_bytes
```

**Step 2: Commit**

```bash
git add logstash-configs/outputs/dynatrace/output.conf
git commit -m "Add new MITM fields to Dynatrace log payload

Include reason, session_id, sid, request_bytes, response_bytes in
the Dynatrace log event for L7 DCF events."
```

---

## Task 5: Create VPNSession Filter

**Files:**
- Create: `logstash-configs/filters/18-vpn-session.conf`

**Step 1: Create the filter file**

```ruby
# VPN Session Filter
# Parses AviatrixVPNSession syslog messages (connect/disconnect events)

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

**Step 2: Commit**

```bash
git add logstash-configs/filters/18-vpn-session.conf
git commit -m "Add AviatrixVPNSession filter for VPN connect/disconnect logs

New filter parses VPN session events with 13 fields including user,
status, gateway, IPs, duration, and byte counts. Tag: vpn_session."
```

---

## Task 6: Add VPNSession Test Samples

**Files:**
- Modify: `test-tools/sample-logs/test-samples.log` (before the "ADDITIONAL LOG TYPES" section at line 194)

**Step 1: Add VPN session test samples**

Insert before line 194 (`###...ADDITIONAL LOG TYPES...`):

```
###############################################################################
# VPN SESSION LOGS - AviatrixVPNSession
###############################################################################

# --- VPN connect event (Status=active, N/A fields for duration/bytes) ---
Feb 25 00:23:01 ip-172-31-46-24 cloudxd: AviatrixVPNSession: User=demo, Status=active, Gateway=vpn-gw-1, GatewayIP=52.52.76.149, VPNVirtualIP=192.168.0.6, PublicIP=203.0.113.45, Login=2026-02-25 00:22:58, Logout=N/A, Duration=N/A, RXbytes=N/A, TXbytes=N/A, VPNClientPlatform=Windows, VPNClientVersion=2.14.14

# --- VPN disconnect event (Status=disconnected, filled duration/bytes) ---
Feb 25 00:41:59 ip-172-31-46-24 cloudxd: AviatrixVPNSession: User=demo, Status=disconnected, Gateway=vpn-gw-1, GatewayIP=52.52.76.149, VPNVirtualIP=192.168.0.6, PublicIP=N/A, Login=2026-02-25 00:22:58, Logout=2026-02-25 00:41:57, Duration=0:0:18:59, RXbytes=2.1 MB, TXbytes=9.03 MB, VPNClientPlatform=Windows, VPNClientVersion=2.14.14
```

**Step 2: Update the file header comment** (line 6-17) to include VPN sessions:

Add `# - AviatrixVPNSession (VPN connect/disconnect events)` after the existing list.

**Step 3: Commit**

```bash
git add test-tools/sample-logs/test-samples.log
git commit -m "Add VPN session test samples

Two samples: connect (Status=active) and disconnect (Status=disconnected)
with duration and byte counts."
```

---

## Task 7: Add VPNSession Output Block — Splunk HEC

**Files:**
- Modify: `logstash-configs/outputs/splunk-hec/output.conf` (before the closing `}` of the output block, after tunnel_status block ending at line 223)

**Step 1: Add vpn_session output block**

Insert before line 224 (the final `}`):

```ruby

    # VPN session events
    else if "vpn_session" in [tags] and ("${LOG_PROFILE:all}" == "all" or "${LOG_PROFILE:all}" == "security") {
        http {
            id => "splunk-vpn-session"
            http_method => "post"
            url => "${SPLUNK_ADDRESS}:${SPLUNK_PORT:8088}/services/collector/event"
            headers => ["Authorization", "Splunk ${SPLUNK_HEC_AUTH}"]
            ssl_verification_mode => "none"
            format => "json"
            mapping => {
                "sourcetype" => "aviatrix:vpn:session"
                "source" => "avx-vpn-session"
                "host" => "%{vpn_gateway}"
                "time" => "%{unix_time}"
                "event" => {
                    "vpn_user" => "%{vpn_user}"
                    "vpn_status" => "%{vpn_status}"
                    "vpn_gateway" => "%{vpn_gateway}"
                    "vpn_gateway_ip" => "%{vpn_gateway_ip}"
                    "vpn_virtual_ip" => "%{vpn_virtual_ip}"
                    "vpn_public_ip" => "%{vpn_public_ip}"
                    "vpn_login" => "%{vpn_login}"
                    "vpn_logout" => "%{vpn_logout}"
                    "vpn_duration" => "%{vpn_duration}"
                    "vpn_rx_bytes" => "%{vpn_rx_bytes}"
                    "vpn_tx_bytes" => "%{vpn_tx_bytes}"
                    "vpn_client_platform" => "%{vpn_client_platform}"
                    "vpn_client_version" => "%{vpn_client_version}"
                    "syslog" => "%{message}"
                }
            }
        }
    }
```

**Step 2: Update the header comment** (lines 10-11) to add `vpn_session` to the security profile list.

**Step 3: Commit**

```bash
git add logstash-configs/outputs/splunk-hec/output.conf
git commit -m "Add VPN session output block for Splunk HEC

Routes vpn_session events to Splunk with sourcetype aviatrix:vpn:session,
gated on security LOG_PROFILE."
```

---

## Task 8: Add VPNSession Output Block — Webhook Test

**Files:**
- Modify: `logstash-configs/outputs/webhook-test/output.conf` (before the closing `}`, after tunnel_status block ending at line 183)

**Step 1: Add vpn_session output block**

Insert before line 184 (the final `}`):

```ruby

    # VPN session events
    else if "vpn_session" in [tags] {
        http {
            id => "webhook-vpn-session"
            http_method => "post"
            url => "${WEBHOOK_URL}"
            format => "json"
            mapping => {
                "type" => "vpn_session"
                "host" => "%{vpn_gateway}"
                "event" => {
                    "vpn_user" => "%{vpn_user}"
                    "vpn_status" => "%{vpn_status}"
                    "vpn_gateway" => "%{vpn_gateway}"
                    "vpn_gateway_ip" => "%{vpn_gateway_ip}"
                    "vpn_virtual_ip" => "%{vpn_virtual_ip}"
                    "vpn_public_ip" => "%{vpn_public_ip}"
                    "vpn_login" => "%{vpn_login}"
                    "vpn_logout" => "%{vpn_logout}"
                    "vpn_duration" => "%{vpn_duration}"
                    "vpn_rx_bytes" => "%{vpn_rx_bytes}"
                    "vpn_tx_bytes" => "%{vpn_tx_bytes}"
                    "vpn_client_platform" => "%{vpn_client_platform}"
                    "vpn_client_version" => "%{vpn_client_version}"
                }
                "source" => "avx-vpn-session"
                "time" => "%{unix_time}"
            }
        }
    }
```

**Step 2: Commit**

```bash
git add logstash-configs/outputs/webhook-test/output.conf
git commit -m "Add VPN session output block for webhook test"
```

---

## Task 9: Add VPNSession Output Block — Azure Log Ingestion

**Files:**
- Modify: `logstash-configs/outputs/azure-log-ingestion/output.conf`

**Step 1: Add pre-processing filter block**

Insert after the tunnel status pre-processing filter (after line 410), before the `output {` block:

```ruby

# VPN Session pre-processing for Azure
filter {
    if "vpn_session" in [tags] {
        ruby {
            id => "vpn-session-azure-timegen"
            code => "event.set('TimeGenerated', event.get('@timestamp'))"
        }

        mutate {
            id => "vpn-session-azure-cleanup"
            remove_field => ["message", "host", "port", "type", "event", "@version", "syslog_pri"]
        }
    }
}
```

**Step 2: Add output block**

Insert before the final `}` of the output block (before line 510):

```ruby

    # VPN Session events → AviatrixVPNSession_CL
    else if "vpn_session" in [tags] and ("${LOG_PROFILE:all}" == "all" or "${LOG_PROFILE:all}" == "security") {
        microsoft-sentinel-log-analytics-logstash-output-plugin {
            id => "azure-vpn-session"
            client_app_Id => "${client_app_id}"
            client_app_secret => "${client_app_secret}"
            tenant_id => "${tenant_id}"
            data_collection_endpoint => "${data_collection_endpoint}"
            dcr_immutable_id => "${azure_dcr_vpn_session_id}"
            dcr_stream_name => "${azure_stream_vpn_session}"
            azure_cloud => "${azure_cloud}"
        }
    }
```

**Step 3: Commit**

```bash
git add logstash-configs/outputs/azure-log-ingestion/output.conf
git commit -m "Add VPN session output block for Azure Log Analytics

Routes to AviatrixVPNSession_CL table, gated on security LOG_PROFILE.
New env vars: azure_dcr_vpn_session_id, azure_stream_vpn_session."
```

---

## Task 10: Add VPNSession to Dynatrace Logs

**Files:**
- Modify: `logstash-configs/outputs/dynatrace/output.conf`

**Step 1: Add Ruby log builder for VPN session**

Insert after the suricata log builder filter block (before the `# OUTPUT` section comment around line 574):

```ruby

# Build Dynatrace log payload for VPN session events
filter {
    if "vpn_session" in [tags] {
        ruby {
            id => "dynatrace-build-vpn-session-log"
            code => '
                resolve = lambda { |v| (v.nil? || v.to_s.include?("%{")) ? "" : v.to_s }

                vpn_user = resolve.call(event.get("vpn_user"))
                vpn_status = resolve.call(event.get("vpn_status"))
                vpn_gateway = resolve.call(event.get("vpn_gateway"))
                vpn_gateway_ip = resolve.call(event.get("vpn_gateway_ip"))
                vpn_public_ip = resolve.call(event.get("vpn_public_ip"))
                source = ENV.fetch("DT_LOG_SOURCE", ENV.fetch("DT_METRIC_SOURCE", "aviatrix"))

                severity = vpn_status.downcase == "disconnected" ? "INFORMATIONAL" : "INFORMATIONAL"
                content = "VPN #{vpn_status}: #{vpn_user} on #{vpn_gateway}"

                ts = event.get("@timestamp")
                timestamp = ts ? ts.to_iso8601 : Time.now.utc.iso8601(3)

                log_event = {
                    "timestamp" => timestamp,
                    "severity" => severity,
                    "content" => content,
                    "log.source" => source,
                    "aviatrix.event.type" => "VPNSession",
                    "aviatrix.vpn.user" => vpn_user,
                    "aviatrix.vpn.status" => vpn_status,
                    "aviatrix.vpn.gateway" => vpn_gateway,
                    "aviatrix.vpn.gateway_ip" => vpn_gateway_ip
                }
                log_event["aviatrix.vpn.public_ip"] = vpn_public_ip unless vpn_public_ip.empty? || vpn_public_ip == "N/A"

                event.set("[@metadata][dt_log_payload]", "[" + log_event.to_json + "]")
            '
        }
    }
}
```

**Step 2: Add `vpn_session` to the logs output condition**

In the output block (around line 601), update the tag check to include `vpn_session`:

Change:
```ruby
        if (("suricata" in [tags] or "mitm" in [tags] or "microseg" in [tags] or "fqdn" in [tags] or "cmd" in [tags]) and ("${LOG_PROFILE:all}" == "all" or "${LOG_PROFILE:all}" == "security"))
```

To:
```ruby
        if (("suricata" in [tags] or "mitm" in [tags] or "microseg" in [tags] or "fqdn" in [tags] or "cmd" in [tags] or "vpn_session" in [tags]) and ("${LOG_PROFILE:all}" == "all" or "${LOG_PROFILE:all}" == "security"))
```

**Step 3: Commit**

```bash
git add logstash-configs/outputs/dynatrace/output.conf
git commit -m "Add VPN session log builder and output gate for Dynatrace"
```

---

## Task 11: Update Documentation

**Files:**
- Modify: `CONTRIBUTING.md` (Log Profiles tables)
- Modify: `CLAUDE.md` (Log Types Processed table, directory structure)

**Step 1: Update CONTRIBUTING.md**

In the Standard Profiles table, update `all` count and add vpn_session:
- Change `All 8 log types` → `All 9 log types`
- Add `vpn_session` to the `security` profile description

In the Log Type to Profile Mapping table, add:
```
| `vpn_session` | security |
```

**Step 2: Update CLAUDE.md**

In the "Log Types Processed" table, add:
```
| `vpn_session` | VPN connect/disconnect | `AviatrixVPNSession` |
```

In the directory structure, add `18-vpn-session.conf` under filters.

**Step 3: Commit**

```bash
git add CONTRIBUTING.md CLAUDE.md
git commit -m "Update docs for VPN session log type and new MITM fields"
```

---

## Task 12: Reassemble Configs and Validate

**Step 1: Reassemble all output configs**

```bash
cd logstash-configs
./scripts/assemble-config.sh splunk-hec
./scripts/assemble-config.sh azure-log-ingestion
```

**Step 2: Validate assembled configs with Logstash**

```bash
docker run --rm \
  -v $(pwd)/assembled:/config \
  -v $(pwd)/patterns:/usr/share/logstash/patterns \
  docker.elastic.co/logstash/logstash:8.11.0 \
  logstash -f /config/splunk-hec-full.conf --config.test_and_exit
```

Repeat for azure-log-ingestion-full.conf.

Expected: `Configuration OK` from Logstash.

**Step 3: Commit assembled configs**

```bash
git add logstash-configs/assembled/
git commit -m "Reassemble configs with VPN session and MITM field changes"
```

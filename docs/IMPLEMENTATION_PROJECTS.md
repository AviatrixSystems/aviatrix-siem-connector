# Implementation Projects

This document contains detailed instructions for implementing three separate projects to enhance the Aviatrix Log Integration Engine.

---

## Project 1: Modularize Logstash Configuration

### Objective
Refactor the repository to support modular Logstash configuration files, eliminating duplication across output configs and enabling mix-and-match filter/output combinations.

### Current State
- Monolithic config files: Each output config (`output_splunk_hec/`, `output_azure_log_ingestion_api/`) contains duplicated input and filter blocks
- ~400 lines of filter logic duplicated across 3+ config files
- Changes to parsing logic require updates in multiple places
- Pattern file (`base_config/patterns/avx.conf`) is minimal and underutilized

### Target State
```
logstash-configs/
├── inputs/
│   └── 00-syslog-input.conf           # Shared UDP/TCP 5000 input
├── filters/
│   ├── 10-fqdn.conf                   # FQDN rule parsing
│   ├── 11-cmd.conf                    # Controller CMD/API parsing
│   ├── 12-microseg.conf               # L4 microseg parsing (legacy + 8.2)
│   ├── 13-l7-dcf.conf                 # L7 DCF/MITM parsing (legacy + 8.2)
│   ├── 14-suricata.conf               # Suricata IDS parsing
│   ├── 15-gateway-stats.conf          # gw_net_stats, gw_sys_stats
│   ├── 16-tunnel-status.conf          # Tunnel state changes
│   ├── 80-throttle.conf               # Microseg throttling
│   ├── 90-timestamp.conf              # Date normalization
│   └── 95-field-conversion.conf       # Type conversions
├── outputs/
│   ├── splunk-hec/
│   │   ├── output.conf                # Splunk HEC output block only
│   │   └── docker_run.tftpl           # Docker run template
│   ├── azure-log-ingestion/
│   │   ├── output.conf                # Azure Log Ingestion output block only
│   │   └── docker_run.tftpl
│   └── elasticsearch/
│       └── output.conf                # ES output (from origin_logstash.conf)
├── patterns/
│   └── avx.conf                       # Enhanced grok patterns
├── assembled/                          # Pre-assembled configs for deployment
│   ├── splunk-hec-full.conf
│   ├── azure-lia-full.conf
│   └── elasticsearch-full.conf
└── scripts/
    └── assemble-config.sh             # Script to combine modules
```

### Implementation Steps

#### Step 1: Create Enhanced Pattern File
**File:** `logstash-configs/patterns/avx.conf`

Add these patterns to support both legacy and 8.2 log formats:
```
# Existing patterns
SYSLOG_TIMESTAMP (%{TIMESTAMP_ISO8601}|(%{MONTH} +%{MONTHDAY} +%{TIME}))
TUNNEL_GW %{NOTSPACE}(%{NOTSPACE} %{NOTSPACE})

# New patterns for 8.2
AVX_GATEWAY_HOST GW-%{HOSTNAME:gw_hostname}-%{IP:gw_ip}
AVX_MICROSEG_HEADER microseg:|AviatrixGwMicrosegPacket:
AVX_L7_HEADER ats_dcf:|traffic_server(\[%{NUMBER}\]:)?
AVX_SESSION_FIELDS (SESSION_EVENT=%{NUMBER:session_event} SESSION_END_REASON=%{NUMBER:session_end_reason} SESSION_PACKET_COUNT=%{NUMBER:session_packet_count} SESSION_BYTE_COUNT=%{NUMBER:session_byte_count} SESSION_DURATION=%{NUMBER:session_duration_ns})?
```

#### Step 2: Create Modular Input Config
**File:** `logstash-configs/inputs/00-syslog-input.conf`

```ruby
input {
    udp {
        port => 5000
        type => syslog
    }
    tcp {
        port => 5000
        type => syslog
    }
}
```

#### Step 3: Create Individual Filter Modules

Each filter module should:
1. Check `[type] == "syslog"`
2. Exclude already-tagged events
3. Add appropriate tags on match
4. Have a unique filter `id`

**Example - File:** `logstash-configs/filters/12-microseg.conf`

```ruby
# L4 Microseg Filter - Supports legacy and 8.2 formats
filter {
    if [type] == "syslog" and !("fqdn" in [tags] or "cmd" in [tags]) {
        grok {
            id => "microseg-grok"
            patterns_dir => ["/usr/share/logstash/patterns"]
            break_on_match => true
            add_tag => ["microseg", "l4"]
            remove_tag => ["_grokparsefailure"]
            match => {
                "message" => [
                    # 8.2 format with session fields
                    "^<%{NUMBER:syslog_pri}>%{SYSLOG_TIMESTAMP:date} %{HOSTNAME:gw_hostname} microseg: POLICY=%{UUID:policy_uuid} SRC_MAC=%{MAC:src_mac} DST_MAC=%{MAC:dst_mac} IP_SZ=%{NUMBER:ip_size} SRC_IP=%{IP:src_ip} DST_IP=%{IP:dst_ip} PROTO=%{WORD:proto} SRC_PORT=%{NUMBER:src_port} DST_PORT=%{NUMBER:dst_port} DATA=%{NOTSPACE} ACT=%{WORD:act} ENFORCED=%{WORD:enforced}( SESSION_EVENT=%{NUMBER:session_event} SESSION_END_REASON=%{NUMBER:session_end_reason} SESSION_PACKET_COUNT=%{NUMBER:packets} SESSION_BYTE_COUNT=%{NUMBER:bytes} SESSION_DURATION=%{NUMBER:duration_ns})?",

                    # Legacy 7.x format
                    "^<%{NUMBER}>%{SPACE}(%{MONTH} +%{MONTHDAY} +%{TIME} +%{HOSTNAME}-%{IP} syslog )?%{SYSLOG_TIMESTAMP:date} +GW-%{HOSTNAME:gw_hostname}-%{IP} +%{PATH}(\[%{NUMBER}\]:)? +%{YEAR}\/%{SPACE}%{MONTHNUM}\/%{SPACE}%{MONTHDAY} +%{TIME} +AviatrixGwMicrosegPacket: POLICY=%{UUID:policy_uuid} SRC_MAC=%{MAC:src_mac} DST_MAC=%{MAC:dst_mac} IP_SZ=%{NUMBER} SRC_IP=%{IP:src_ip} DST_IP=%{IP:dst_ip} PROTO=%{WORD:proto} SRC_PORT=%{NUMBER:src_port} DST_PORT=%{NUMBER:dst_port} DATA=%{GREEDYDATA} ACT=%{WORD:act} ENFORCED=%{WORD:enforced}"
                ]
            }
        }
    }
}
```

#### Step 4: Create Output-Only Modules

Each output module should contain ONLY the output block with conditional routing.

**Example - File:** `logstash-configs/outputs/splunk-hec/output.conf`

```ruby
output {
    if "suricata" in [tags] {
        http {
            id => "splunk-suricata"
            # ... splunk config
        }
    }
    else if "microseg" in [tags] {
        http {
            id => "splunk-microseg"
            # ... splunk config
        }
    }
    # ... other outputs
}
```

#### Step 5: Create Assembly Script
**File:** `logstash-configs/scripts/assemble-config.sh`

```bash
#!/bin/bash
# Assembles modular configs into a single deployable config file
# Usage: ./assemble-config.sh <output-type> <destination>
# Example: ./assemble-config.sh splunk-hec ./assembled/splunk-hec-full.conf

OUTPUT_TYPE=$1
DEST=$2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

cat "$CONFIG_DIR/inputs/"*.conf > "$DEST"
cat "$CONFIG_DIR/filters/"*.conf >> "$DEST"
cat "$CONFIG_DIR/outputs/$OUTPUT_TYPE/output.conf" >> "$DEST"

echo "Assembled config written to $DEST"
```

#### Step 6: Update Terraform Deployments

Modify Terraform to upload multiple config files or the assembled config:

**Option A:** Upload assembled config (simpler)
- Run assembly script before `terraform apply`
- Upload single file to S3/Azure Storage

**Option B:** Upload individual modules (more flexible)
- Modify S3 upload to handle multiple files
- Update container volume mounts to include all config directories

#### Step 7: Update CLAUDE.md

Add documentation about the new modular structure.

### Acceptance Criteria
- [ ] All filter logic exists in exactly one place
- [ ] Adding a new output destination requires only creating a new output module
- [ ] Existing deployments continue to work with assembled configs
- [ ] Pattern file contains all custom patterns
- [ ] Assembly script can produce working configs for all output types
- [ ] Tests pass with assembled configs (if tests exist)

### Files to Create
1. `logstash-configs/inputs/00-syslog-input.conf`
2. `logstash-configs/filters/10-fqdn.conf`
3. `logstash-configs/filters/11-cmd.conf`
4. `logstash-configs/filters/12-microseg.conf`
5. `logstash-configs/filters/13-l7-dcf.conf`
6. `logstash-configs/filters/14-suricata.conf`
7. `logstash-configs/filters/15-gateway-stats.conf`
8. `logstash-configs/filters/16-tunnel-status.conf`
9. `logstash-configs/filters/80-throttle.conf`
10. `logstash-configs/filters/90-timestamp.conf`
11. `logstash-configs/filters/95-field-conversion.conf`
12. `logstash-configs/outputs/splunk-hec/output.conf`
13. `logstash-configs/outputs/azure-log-ingestion/output.conf`
14. `logstash-configs/scripts/assemble-config.sh`

### Files to Modify
1. `logstash-configs/patterns/avx.conf` - Enhance with new patterns
2. `deployment-tf/aws-ec2-single-instance/main.tf` - Update S3 upload logic
3. `deployment-tf/aws-ec2-autoscale/main.tf` - Update S3 upload logic
4. `CLAUDE.md` - Document new structure

### Files to Deprecate (keep for reference)
1. `logstash-configs/output_splunk_hec/logstash_output_splunk_hec.conf`
2. `logstash-configs/output_splunk_hec/logstash_output_splunk_hec_all.conf`
3. `logstash-configs/output_azure_log_ingestion_api/logstash_output_azure_lia.conf`

---

## Project 2: Splunk CIM-Compliant Exporter with DCF 8.2 Support

### Objective
Create a new Splunk HEC exporter that:
1. Outputs fields compliant with Splunk Common Information Model (CIM)
2. Supports Aviatrix 8.2 DCF session fields
3. Uses consolidated output blocks to reduce duplication

### Target CIM Data Models
- **Network Traffic** - For microseg (L4), L7/DCF, FQDN logs
- **Intrusion Detection** - For Suricata IDS logs

### CIM Field Mapping Reference

#### Network Traffic CIM Fields (L4/L7)
| Aviatrix Field | CIM Field | Type | Transform |
|----------------|-----------|------|-----------|
| `src_ip` / `SRC_IP` | `src`, `src_ip` | string | Direct |
| `dst_ip` / `DST_IP` | `dest`, `dest_ip` | string | Rename |
| `src_port` / `SRC_PORT` | `src_port` | integer | Direct |
| `dst_port` / `DST_PORT` | `dest_port` | integer | Rename |
| `proto` / `PROTO` | `transport` | string | Rename + lowercase |
| `act` / `ACT` / `action` | `action` | string | Map: PERMIT/CONTINUE/ALLOW→allowed, DENY/DROP→blocked |
| `SESSION_BYTE_COUNT` / `request_bytes+response_bytes` | `bytes` | integer | Sum for L7 |
| `request_bytes` | `bytes_out` | integer | L7 only |
| `response_bytes` | `bytes_in` | integer | L7 only |
| `SESSION_PACKET_COUNT` | `packets` | integer | L4 only |
| `SESSION_DURATION` / `session_time` | `duration` | float | Convert ns→seconds |
| `policy_uuid` / `decided_by` | `rule_id` | string | Rename |
| `enforced` / `ENFORCED` | `rule_action` | string | Map: true→enforced, false→monitored |
| `gw_hostname` / `gateway` | `dvc` | string | Device name |
| — | `vendor_product` | string | Static: "Aviatrix" |
| `sni_hostname` | `dest_name` | string | L7 only |
| `url` | `url` | string | L7 only |
| `session_id` | `session_id` | string | L7 only |

#### Intrusion Detection CIM Fields (Suricata)
| Aviatrix Field | CIM Field | Type | Transform |
|----------------|-----------|------|-----------|
| `suricataDataJson.src_ip` | `src`, `src_ip` | string | Extract |
| `suricataDataJson.dest_ip` | `dest`, `dest_ip` | string | Extract |
| `suricataDataJson.src_port` | `src_port` | integer | Extract |
| `suricataDataJson.dest_port` | `dest_port` | integer | Extract |
| `suricataDataJson.proto` | `transport` | string | Extract + lowercase |
| `suricataDataJson.alert.signature` | `signature` | string | Extract |
| `suricataDataJson.alert.signature_id` | `signature_id` | string | Extract |
| `suricataDataJson.alert.category` | `category` | string | Extract |
| `suricataDataJson.alert.severity` | `severity` | string | Map: 1→high, 2→medium, 3→low, 4→informational |
| `gw_hostname` | `dvc` | string | Device |
| — | `vendor_product` | string | Static: "Aviatrix Suricata" |
| — | `ids_type` | string | Static: "network" |

### Implementation Steps

#### Step 1: Create CIM Normalization Filter
**File:** `logstash-configs/filters/96-cim-normalize.conf`

This filter transforms parsed fields to CIM-compliant names and values.

```ruby
# CIM Normalization Filter
# Transforms Aviatrix fields to Splunk CIM-compliant fields

# L4 Microseg CIM Normalization
filter {
    if "microseg" in [tags] and "l7" not in [tags] {
        mutate {
            id => "cim-microseg-rename"
            rename => {
                "dst_ip" => "dest_ip"
                "dst_port" => "dest_port"
                "policy_uuid" => "rule_id"
            }
            add_field => {
                "src" => "%{src_ip}"
                "dest" => "%{dest_ip}"
                "dvc" => "%{gw_hostname}"
                "vendor_product" => "Aviatrix DCF"
            }
            lowercase => ["proto"]
        }

        mutate {
            id => "cim-microseg-transport"
            rename => { "proto" => "transport" }
        }

        # Map action to CIM values
        if [act] in ["PERMIT", "CONTINUE", "ALLOW"] {
            mutate {
                id => "cim-microseg-action-allowed"
                add_field => { "action" => "allowed" }
            }
        } else if [act] in ["DENY", "DROP"] {
            mutate {
                id => "cim-microseg-action-blocked"
                add_field => { "action" => "blocked" }
            }
        }

        # Map enforced to rule_action
        if [enforced] == "true" {
            mutate {
                id => "cim-microseg-enforced"
                add_field => { "rule_action" => "enforced" }
            }
        } else {
            mutate {
                id => "cim-microseg-monitored"
                add_field => { "rule_action" => "monitored" }
            }
        }

        # Convert duration from nanoseconds to seconds (8.2 only)
        if [duration_ns] {
            ruby {
                id => "cim-microseg-duration"
                code => 'event.set("duration", event.get("duration_ns").to_f / 1_000_000_000)'
            }
        }

        # Map session_end_reason (8.2 only)
        if [session_end_reason] == "1" {
            mutate { add_field => { "session_end_type" => "fin" } }
        } else if [session_end_reason] == "2" {
            mutate { add_field => { "session_end_type" => "rst" } }
        } else if [session_end_reason] == "3" {
            mutate { add_field => { "session_end_type" => "timeout" } }
        }

        # Rename 8.2 session fields to CIM
        if [session_event] {
            mutate {
                id => "cim-microseg-session-fields"
                rename => {
                    "session_packet_count" => "packets"
                    "session_byte_count" => "bytes"
                }
            }
        }

        # Cleanup intermediate fields
        mutate {
            id => "cim-microseg-cleanup"
            remove_field => ["act", "duration_ns", "session_end_reason", "session_event", "ip_size", "syslog_pri"]
        }
    }
}

# L7 DCF CIM Normalization
filter {
    if "l7" in [tags] and [l7] {
        mutate {
            id => "cim-l7-fields"
            add_field => {
                "session_id" => "%{[l7][session_id]}"
                "session_stage" => "%{[l7][session_stage]}"
                "dest_name" => "%{[l7][sni_hostname]}"
                "url" => "%{[l7][url]}"
                "rule_id" => "%{[l7][decided_by]}"
                "transport" => "%{[l7][proto]}"
                "dvc" => "%{gw_hostname}"
                "vendor_product" => "Aviatrix DCF L7"
            }
            lowercase => ["transport"]
        }

        # Map action
        if [l7][action] == "PERMIT" {
            mutate { add_field => { "action" => "allowed" } }
        } else {
            mutate { add_field => { "action" => "blocked" } }
        }

        # Map enforced
        if [l7][enforced] == true {
            mutate { add_field => { "rule_action" => "enforced" } }
        } else {
            mutate { add_field => { "rule_action" => "monitored" } }
        }

        # Handle byte counts (session end only)
        if [l7][request_bytes] {
            ruby {
                id => "cim-l7-bytes"
                code => '
                    req = event.get("[l7][request_bytes]").to_i
                    resp = event.get("[l7][response_bytes]").to_i
                    event.set("bytes_out", req)
                    event.set("bytes_in", resp)
                    event.set("bytes", req + resp)
                '
            }
        }

        # Convert session_time ns to seconds
        if [l7][session_time] {
            ruby {
                id => "cim-l7-duration"
                code => 'event.set("duration", event.get("[l7][session_time]").to_f / 1_000_000_000)'
            }
        }

        # TLS error handling
        if [l7][message] {
            mutate { add_field => { "ssl_error" => "%{[l7][message]}" } }
        }
    }
}

# Suricata IDS CIM Normalization
filter {
    if "suricata" in [tags] and [suricataDataJson] {
        mutate {
            id => "cim-suricata-fields"
            add_field => {
                "src" => "%{[suricataDataJson][src_ip]}"
                "src_ip" => "%{[suricataDataJson][src_ip]}"
                "dest" => "%{[suricataDataJson][dest_ip]}"
                "dest_ip" => "%{[suricataDataJson][dest_ip]}"
                "src_port" => "%{[suricataDataJson][src_port]}"
                "dest_port" => "%{[suricataDataJson][dest_port]}"
                "transport" => "%{[suricataDataJson][proto]}"
                "signature" => "%{[suricataDataJson][alert][signature]}"
                "signature_id" => "%{[suricataDataJson][alert][signature_id]}"
                "category" => "%{[suricataDataJson][alert][category]}"
                "dvc" => "%{gw_hostname}"
                "vendor_product" => "Aviatrix Suricata"
                "ids_type" => "network"
            }
            lowercase => ["transport"]
        }

        # Map severity (Suricata: 1=high, 2=medium, 3=low)
        if [suricataDataJson][alert][severity] == 1 {
            mutate { add_field => { "severity" => "high" } }
        } else if [suricataDataJson][alert][severity] == 2 {
            mutate { add_field => { "severity" => "medium" } }
        } else if [suricataDataJson][alert][severity] == 3 {
            mutate { add_field => { "severity" => "low" } }
        } else {
            mutate { add_field => { "severity" => "informational" } }
        }

        # Type conversions
        mutate {
            id => "cim-suricata-types"
            convert => {
                "src_port" => "integer"
                "dest_port" => "integer"
            }
        }
    }
}

# FQDN CIM Normalization
filter {
    if "fqdn" in [tags] and "l7" not in [tags] {
        mutate {
            id => "cim-fqdn-fields"
            rename => {
                "sip" => "src_ip"
                "dip" => "dest_ip"
            }
            add_field => {
                "src" => "%{src_ip}"
                "dest" => "%{dest_ip}"
                "dest_name" => "%{hostname}"
                "dvc" => "%{gateway}"
                "vendor_product" => "Aviatrix FQDN"
            }
        }

        # Map state to action
        if [state] in ["MATCHED", "ALLOWED"] {
            mutate { add_field => { "action" => "allowed" } }
        } else {
            mutate { add_field => { "action" => "blocked" } }
        }
    }
}
```

#### Step 2: Create Splunk Metadata Builder Filter
**File:** `logstash-configs/filters/97-splunk-metadata.conf`

Build Splunk HEC metadata fields for consolidated output:

```ruby
# Build Splunk metadata for consolidated output
filter {
    # Set sourcetype and source based on log type
    if "suricata" in [tags] {
        mutate {
            id => "splunk-meta-suricata"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:ids"
                "[@metadata][splunk_source]" => "avx-suricata"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_SECURITY:main}"
            }
        }
    }
    else if "l7" in [tags] {
        mutate {
            id => "splunk-meta-l7"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:dcf:l7"
                "[@metadata][splunk_source]" => "avx-l7-fw"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_NETWORK:main}"
            }
        }
    }
    else if "microseg" in [tags] {
        mutate {
            id => "splunk-meta-microseg"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:dcf:l4"
                "[@metadata][splunk_source]" => "avx-l4-fw"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_NETWORK:main}"
            }
        }
    }
    else if "fqdn" in [tags] {
        mutate {
            id => "splunk-meta-fqdn"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:fqdn"
                "[@metadata][splunk_source]" => "avx-fqdn"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_NETWORK:main}"
            }
        }
    }
    else if "cmd" in [tags] {
        mutate {
            id => "splunk-meta-cmd"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:audit"
                "[@metadata][splunk_source]" => "avx-cmd"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_AUDIT:main}"
            }
        }
    }
    else if "gw_net_stats" in [tags] {
        mutate {
            id => "splunk-meta-netstats"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:perfmon:network"
                "[@metadata][splunk_source]" => "avx-gw-net-stats"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_METRICS:main}"
            }
        }
    }
    else if "gw_sys_stats" in [tags] {
        mutate {
            id => "splunk-meta-sysstats"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:perfmon:system"
                "[@metadata][splunk_source]" => "avx-gw-sys-stats"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_METRICS:main}"
            }
        }
    }
    else if "tunnel_status" in [tags] {
        mutate {
            id => "splunk-meta-tunnel"
            add_field => {
                "[@metadata][splunk_sourcetype]" => "aviatrix:tunnel"
                "[@metadata][splunk_source]" => "avx-tunnel-status"
                "[@metadata][splunk_index]" => "${SPLUNK_INDEX_NETWORK:main}"
            }
        }
    }
}
```

#### Step 3: Create Consolidated Splunk Output
**File:** `logstash-configs/outputs/splunk-hec-cim/output.conf`

```ruby
# Splunk HEC Output - CIM Compliant
# Single output block for all event types

output {
    if [@metadata][splunk_sourcetype] {
        http {
            id => "splunk-hec-cim"
            http_method => "post"
            url => "${SPLUNK_SCHEME:https}://${SPLUNK_ADDRESS}:${SPLUNK_PORT:8088}/services/collector/event"
            headers => ["Authorization", "Splunk ${SPLUNK_HEC_TOKEN}"]
            ssl_verification_mode => "${SPLUNK_SSL_VERIFY:none}"
            cacert => "${SPLUNK_CA_CERT:}"
            format => "json"
            pool_max => 50
            pool_max_per_route => 25
            retry_non_idempotent => true
            automatic_retries => 3

            mapping => {
                "time" => "%{unix_time}"
                "host" => "%{dvc}"
                "source" => "%{[@metadata][splunk_source]}"
                "sourcetype" => "%{[@metadata][splunk_sourcetype]}"
                "index" => "%{[@metadata][splunk_index]}"
                "event" => {
                    # CIM Network Traffic fields
                    "src" => "%{src}"
                    "src_ip" => "%{src_ip}"
                    "src_port" => "%{src_port}"
                    "dest" => "%{dest}"
                    "dest_ip" => "%{dest_ip}"
                    "dest_port" => "%{dest_port}"
                    "dest_name" => "%{dest_name}"
                    "transport" => "%{transport}"
                    "action" => "%{action}"
                    "bytes" => "%{bytes}"
                    "bytes_in" => "%{bytes_in}"
                    "bytes_out" => "%{bytes_out}"
                    "packets" => "%{packets}"
                    "duration" => "%{duration}"
                    "url" => "%{url}"

                    # CIM IDS fields
                    "signature" => "%{signature}"
                    "signature_id" => "%{signature_id}"
                    "category" => "%{category}"
                    "severity" => "%{severity}"
                    "ids_type" => "%{ids_type}"

                    # Session fields
                    "session_id" => "%{session_id}"
                    "session_stage" => "%{session_stage}"
                    "session_end_type" => "%{session_end_type}"

                    # Policy fields
                    "rule_id" => "%{rule_id}"
                    "rule_action" => "%{rule_action}"

                    # Device context
                    "dvc" => "%{dvc}"
                    "vendor_product" => "%{vendor_product}"

                    # TLS fields (L7)
                    "ssl_error" => "%{ssl_error}"

                    # Raw syslog for reference
                    "raw_log" => "%{message}"
                }
            }
        }
    }
}
```

#### Step 4: Create Docker Run Template
**File:** `logstash-configs/outputs/splunk-hec-cim/docker_run.tftpl`

```bash
# DOCKER RUN FOR SPLUNK HEC CIM OUTPUT
sudo docker run -d --restart=always \
  --name logstash-aviatrix \
  -v /logstash/pipeline/:/usr/share/logstash/pipeline/ \
  -v /logstash/patterns:/usr/share/logstash/patterns \
  -e SPLUNK_HEC_TOKEN=${splunk_hec_token} \
  -e SPLUNK_ADDRESS=${splunk_address} \
  -e SPLUNK_PORT=${splunk_port} \
  -e SPLUNK_SCHEME=${splunk_scheme} \
  -e SPLUNK_SSL_VERIFY=${splunk_ssl_verify} \
  -e SPLUNK_INDEX_NETWORK=${splunk_index_network} \
  -e SPLUNK_INDEX_SECURITY=${splunk_index_security} \
  -e SPLUNK_INDEX_AUDIT=${splunk_index_audit} \
  -e SPLUNK_INDEX_METRICS=${splunk_index_metrics} \
  -e XPACK_MONITORING_ENABLED=false \
  -p 5000:5000/tcp \
  -p 5000:5000/udp \
  docker.elastic.co/logstash/logstash:8.16.2
```

#### Step 5: Create Splunk TA Configuration Files

**File:** `logstash-configs/outputs/splunk-hec-cim/splunk-ta/props.conf`

```ini
# Aviatrix Technology Add-on for Splunk
# props.conf

[aviatrix:dcf:l4]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json
FIELDALIAS-cim_dest = dest_ip AS dest
FIELDALIAS-cim_src = src_ip AS src

[aviatrix:dcf:l7]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json
FIELDALIAS-cim_dest = dest_name AS dest

[aviatrix:ids]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json
FIELDALIAS-cim_dest = dest_ip AS dest
FIELDALIAS-cim_src = src_ip AS src

[aviatrix:fqdn]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json

[aviatrix:audit]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json

[aviatrix:perfmon:network]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json

[aviatrix:perfmon:system]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json

[aviatrix:tunnel]
SHOULD_LINEMERGE = false
TIME_FORMAT = %s
KV_MODE = json
```

**File:** `logstash-configs/outputs/splunk-hec-cim/splunk-ta/tags.conf`

```ini
# tags.conf - CIM data model tagging

[sourcetype=aviatrix:dcf:l4]
network = enabled
communicate = enabled

[sourcetype=aviatrix:dcf:l7]
network = enabled
communicate = enabled
web = enabled

[sourcetype=aviatrix:ids]
attack = enabled
ids = enabled
network = enabled

[sourcetype=aviatrix:fqdn]
network = enabled
communicate = enabled
dns = enabled

[sourcetype=aviatrix:audit]
change = enabled
audit = enabled

[sourcetype=aviatrix:tunnel]
network = enabled
vpn = enabled
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SPLUNK_ADDRESS` | (required) | Splunk HEC hostname/IP |
| `SPLUNK_PORT` | `8088` | HEC port |
| `SPLUNK_HEC_TOKEN` | (required) | HEC authentication token |
| `SPLUNK_SCHEME` | `https` | `http` or `https` |
| `SPLUNK_SSL_VERIFY` | `none` | `none` or `full` |
| `SPLUNK_CA_CERT` | (empty) | Path to CA cert for SSL |
| `SPLUNK_INDEX_NETWORK` | `main` | Index for network traffic |
| `SPLUNK_INDEX_SECURITY` | `main` | Index for IDS events |
| `SPLUNK_INDEX_AUDIT` | `main` | Index for audit logs |
| `SPLUNK_INDEX_METRICS` | `main` | Index for metrics |

### Acceptance Criteria
- [ ] All log types produce CIM-compliant field names
- [ ] Action values are `allowed` or `blocked` (not PERMIT/DENY)
- [ ] Duration fields are in seconds (not nanoseconds)
- [ ] 8.2 session fields (bytes, packets, duration) are captured
- [ ] L7 session_id enables session correlation
- [ ] Suricata severity is string (high/medium/low/informational)
- [ ] Splunk TA files enable CIM data model acceleration
- [ ] Single output block handles all event types
- [ ] Environment variables control SSL and index routing

### Files to Create
1. `logstash-configs/filters/96-cim-normalize.conf`
2. `logstash-configs/filters/97-splunk-metadata.conf`
3. `logstash-configs/outputs/splunk-hec-cim/output.conf`
4. `logstash-configs/outputs/splunk-hec-cim/docker_run.tftpl`
5. `logstash-configs/outputs/splunk-hec-cim/splunk-ta/props.conf`
6. `logstash-configs/outputs/splunk-hec-cim/splunk-ta/tags.conf`
7. `logstash-configs/outputs/splunk-hec-cim/README.md`

---

## Project 3: AWS ECS Deployment

### Objective
Create a new Terraform deployment that runs the Logstash log integration engine on AWS ECS (Fargate), providing a managed container experience without EC2 instance management.

### Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Region                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                          VPC                               │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              Public Subnet(s)                        │  │  │
│  │  │  ┌─────────────┐    ┌─────────────────────────────┐ │  │  │
│  │  │  │     NLB     │───▶│      ECS Service            │ │  │  │
│  │  │  │ (Elastic IP)│    │  ┌─────────────────────┐    │ │  │  │
│  │  │  │  TCP/UDP    │    │  │  Fargate Task       │    │ │  │  │
│  │  │  │  :5000      │    │  │  ┌───────────────┐  │    │ │  │  │
│  │  │  └─────────────┘    │  │  │   Logstash    │  │    │ │  │  │
│  │  │                     │  │  │   Container   │  │    │ │  │  │
│  │  │                     │  │  └───────────────┘  │    │ │  │  │
│  │  │                     │  └─────────────────────┘    │ │  │  │
│  │  │                     └─────────────────────────────┘ │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   │  │
│  │  │      S3      │   │  CloudWatch  │   │   Secrets    │   │  │
│  │  │   (Config)   │   │    (Logs)    │   │   Manager    │   │  │
│  │  └──────────────┘   └──────────────┘   └──────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Structure
```
deployment-tf/
└── aws-ecs-fargate/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── ecs.tf
    ├── nlb.tf
    ├── iam.tf
    ├── s3.tf
    ├── secrets.tf
    ├── cloudwatch.tf
    ├── terraform.tfvars.sample
    └── README.md
```

### Implementation Steps

#### Step 1: Create Main Terraform Configuration
**File:** `deployment-tf/aws-ecs-fargate/main.tf`

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  name_prefix = "avx-log-${random_string.suffix.result}"
  common_tags = merge(var.tags, {
    Project   = "aviatrix-log-integration"
    ManagedBy = "terraform"
  })
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnets" "selected" {
  filter {
    name   = "subnet-id"
    values = var.subnet_ids
  }
}
```

#### Step 2: Create ECS Cluster and Service
**File:** `deployment-tf/aws-ecs-fargate/ecs.tf`

```hcl
# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
  }
}

# Task Definition
resource "aws_ecs_task_definition" "logstash" {
  family                   = "${local.name_prefix}-logstash"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "logstash"
      image     = var.logstash_image
      essential = true

      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        },
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "udp"
        }
      ]

      environment = [
        {
          name  = "XPACK_MONITORING_ENABLED"
          value = "false"
        },
        {
          name  = "CONFIG_RELOAD_AUTOMATIC"
          value = "true"
        },
        {
          name  = "CONFIG_RELOAD_INTERVAL"
          value = "30s"
        }
      ]

      secrets = [
        {
          name      = "SPLUNK_HEC_TOKEN"
          valueFrom = aws_secretsmanager_secret.splunk_hec_token.arn
        },
        {
          name      = "SPLUNK_ADDRESS"
          valueFrom = "${aws_secretsmanager_secret.splunk_config.arn}:address::"
        },
        {
          name      = "SPLUNK_PORT"
          valueFrom = "${aws_secretsmanager_secret.splunk_config.arn}:port::"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "pipeline-config"
          containerPath = "/usr/share/logstash/pipeline"
          readOnly      = true
        },
        {
          sourceVolume  = "patterns"
          containerPath = "/usr/share/logstash/patterns"
          readOnly      = true
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.logstash.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "logstash"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9600/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    {
      name      = "config-sidecar"
      image     = "amazon/aws-cli:latest"
      essential = false

      command = [
        "/bin/sh", "-c",
        "aws s3 sync s3://${aws_s3_bucket.config.id}/pipeline/ /config/pipeline/ && aws s3 sync s3://${aws_s3_bucket.config.id}/patterns/ /config/patterns/ && sleep infinity"
      ]

      mountPoints = [
        {
          sourceVolume  = "pipeline-config"
          containerPath = "/config/pipeline"
          readOnly      = false
        },
        {
          sourceVolume  = "patterns"
          containerPath = "/config/patterns"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.logstash.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "config-sync"
        }
      }
    }
  ])

  volume {
    name = "pipeline-config"
  }

  volume {
    name = "patterns"
  }

  tags = local.common_tags
}

# ECS Service
resource "aws_ecs_service" "logstash" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.logstash.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tcp.arn
    container_name   = "logstash"
    container_port   = 5000
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.udp.arn
    container_name   = "logstash"
    container_port   = 5000
  }

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Auto Scaling
resource "aws_appautoscaling_target" "ecs" {
  count              = var.enable_autoscaling ? 1 : 0
  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.logstash.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${local.name_prefix}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Security group for Logstash ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description = "Syslog TCP"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Syslog UDP"
    from_port   = 5000
    to_port     = 5000
    protocol    = "udp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Logstash API (health check)"
    from_port   = 9600
    to_port     = 9600
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}
```

#### Step 3: Create Network Load Balancer
**File:** `deployment-tf/aws-ecs-fargate/nlb.tf`

```hcl
# Network Load Balancer
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-nlb"
  internal           = var.internal_nlb
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_cross_zone_load_balancing = true

  tags = local.common_tags
}

# Elastic IP for NLB (if public)
resource "aws_eip" "nlb" {
  count  = var.internal_nlb ? 0 : length(var.subnet_ids)
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-nlb-eip-${count.index}" })
}

# TCP Target Group
resource "aws_lb_target_group" "tcp" {
  name        = "${local.name_prefix}-tcp"
  port        = 5000
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    port                = "9600"
    protocol            = "TCP"
  }

  tags = local.common_tags
}

# UDP Target Group
resource "aws_lb_target_group" "udp" {
  name        = "${local.name_prefix}-udp"
  port        = 5000
  protocol    = "UDP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    port                = "9600"
    protocol            = "TCP"
  }

  tags = local.common_tags
}

# TCP Listener
resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.main.arn
  port              = 5000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp.arn
  }

  tags = local.common_tags
}

# UDP Listener
resource "aws_lb_listener" "udp" {
  load_balancer_arn = aws_lb.main.arn
  port              = 5000
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.udp.arn
  }

  tags = local.common_tags
}
```

#### Step 4: Create IAM Roles
**File:** `deployment-tf/aws-ecs-fargate/iam.tf`

```hcl
# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${local.name_prefix}-secrets-access"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        aws_secretsmanager_secret.splunk_hec_token.arn,
        aws_secretsmanager_secret.splunk_config.arn
      ]
    }]
  })
}

# ECS Task Role
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${local.name_prefix}-s3-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.config.arn,
        "${aws_s3_bucket.config.arn}/*"
      ]
    }]
  })
}
```

#### Step 5: Create S3 Config Bucket
**File:** `deployment-tf/aws-ecs-fargate/s3.tf`

```hcl
# S3 Bucket for Logstash Config
resource "aws_s3_bucket" "config" {
  bucket = "${local.name_prefix}-config"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload Logstash pipeline config
resource "aws_s3_object" "pipeline_config" {
  bucket = aws_s3_bucket.config.id
  key    = "pipeline/logstash.conf"
  source = var.logstash_config_path
  etag   = filemd5(var.logstash_config_path)
  tags   = local.common_tags
}

# Upload patterns
resource "aws_s3_object" "patterns" {
  bucket = aws_s3_bucket.config.id
  key    = "patterns/avx.conf"
  source = var.patterns_config_path
  etag   = filemd5(var.patterns_config_path)
  tags   = local.common_tags
}
```

#### Step 6: Create Secrets Manager Resources
**File:** `deployment-tf/aws-ecs-fargate/secrets.tf`

```hcl
# Splunk HEC Token
resource "aws_secretsmanager_secret" "splunk_hec_token" {
  name        = "${local.name_prefix}/splunk-hec-token"
  description = "Splunk HEC authentication token"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "splunk_hec_token" {
  secret_id     = aws_secretsmanager_secret.splunk_hec_token.id
  secret_string = var.splunk_hec_token
}

# Splunk Config
resource "aws_secretsmanager_secret" "splunk_config" {
  name        = "${local.name_prefix}/splunk-config"
  description = "Splunk connection configuration"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "splunk_config" {
  secret_id = aws_secretsmanager_secret.splunk_config.id
  secret_string = jsonencode({
    address = var.splunk_address
    port    = var.splunk_port
  })
}
```

#### Step 7: Create CloudWatch Resources
**File:** `deployment-tf/aws-ecs-fargate/cloudwatch.tf`

```hcl
# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "logstash" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU utilization high"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.logstash.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${local.name_prefix}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS memory utilization high"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.logstash.name
  }

  tags = local.common_tags
}
```

#### Step 8: Create Variables
**File:** `deployment-tf/aws-ecs-fargate/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# ECS Configuration
variable "logstash_image" {
  description = "Logstash Docker image"
  type        = string
  default     = "docker.elastic.co/logstash/logstash:8.16.2"
}

variable "task_cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 1024  # 1 vCPU
}

variable "task_memory" {
  description = "Fargate task memory (MB)"
  type        = number
  default     = 2048  # 2 GB
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "use_spot" {
  description = "Use Fargate Spot capacity"
  type        = bool
  default     = false
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks"
  type        = bool
  default     = true
}

# Autoscaling
variable "enable_autoscaling" {
  description = "Enable ECS service autoscaling"
  type        = bool
  default     = true
}

variable "min_count" {
  description = "Minimum task count"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum task count"
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 70
}

# Network
variable "internal_nlb" {
  description = "Create internal NLB"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to send syslog"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Splunk Configuration
variable "splunk_address" {
  description = "Splunk HEC hostname"
  type        = string
}

variable "splunk_port" {
  description = "Splunk HEC port"
  type        = string
  default     = "8088"
}

variable "splunk_hec_token" {
  description = "Splunk HEC token"
  type        = string
  sensitive   = true
}

# Logstash Configuration
variable "logstash_config_path" {
  description = "Path to Logstash pipeline config"
  type        = string
  default     = "../../logstash-configs/assembled/splunk-hec-cim-full.conf"
}

variable "patterns_config_path" {
  description = "Path to patterns config"
  type        = string
  default     = "../../logstash-configs/patterns/avx.conf"
}

# Monitoring
variable "enable_container_insights" {
  description = "Enable ECS Container Insights"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
```

#### Step 9: Create Outputs
**File:** `deployment-tf/aws-ecs-fargate/outputs.tf`

```hcl
output "nlb_dns_name" {
  description = "NLB DNS name for syslog destination"
  value       = aws_lb.main.dns_name
}

output "nlb_arn" {
  description = "NLB ARN"
  value       = aws_lb.main.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.logstash.name
}

output "config_bucket" {
  description = "S3 bucket for Logstash configuration"
  value       = aws_s3_bucket.config.id
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for Logstash"
  value       = aws_cloudwatch_log_group.logstash.name
}

output "syslog_endpoint" {
  description = "Syslog endpoint for Aviatrix configuration"
  value       = "${aws_lb.main.dns_name}:5000"
}
```

#### Step 10: Create Sample Variables File
**File:** `deployment-tf/aws-ecs-fargate/terraform.tfvars.sample`

```hcl
aws_region = "us-west-2"
vpc_id     = "vpc-xxxxxxxxx"
subnet_ids = ["subnet-xxxxxx", "subnet-yyyyyy"]

tags = {
  Environment = "production"
  Application = "aviatrix-logging"
}

# ECS Configuration
task_cpu      = 1024
task_memory   = 2048
desired_count = 2

# Autoscaling
enable_autoscaling = true
min_count          = 1
max_count          = 4
cpu_target_value   = 70

# Splunk Configuration
splunk_address   = "splunk.example.com"
splunk_port      = "8088"
splunk_hec_token = "your-hec-token-here"

# Logstash Configuration
logstash_config_path = "../../logstash-configs/assembled/splunk-hec-cim-full.conf"
patterns_config_path = "../../logstash-configs/patterns/avx.conf"
```

### Acceptance Criteria
- [ ] ECS Fargate cluster deploys successfully
- [ ] Tasks receive syslog on port 5000 (TCP and UDP)
- [ ] NLB provides stable endpoint for Aviatrix configuration
- [ ] Secrets are stored in AWS Secrets Manager (not environment variables)
- [ ] Config changes in S3 are picked up by running tasks
- [ ] CloudWatch logs capture Logstash output
- [ ] Autoscaling responds to CPU utilization
- [ ] Health checks properly detect unhealthy tasks
- [ ] Deployment includes README with usage instructions

### Files to Create
1. `deployment-tf/aws-ecs-fargate/main.tf`
2. `deployment-tf/aws-ecs-fargate/variables.tf`
3. `deployment-tf/aws-ecs-fargate/outputs.tf`
4. `deployment-tf/aws-ecs-fargate/ecs.tf`
5. `deployment-tf/aws-ecs-fargate/nlb.tf`
6. `deployment-tf/aws-ecs-fargate/iam.tf`
7. `deployment-tf/aws-ecs-fargate/s3.tf`
8. `deployment-tf/aws-ecs-fargate/secrets.tf`
9. `deployment-tf/aws-ecs-fargate/cloudwatch.tf`
10. `deployment-tf/aws-ecs-fargate/terraform.tfvars.sample`
11. `deployment-tf/aws-ecs-fargate/README.md`

---

## Dependencies Between Projects

```
Project 1 (Modularization)
         │
         ▼
Project 2 (Splunk CIM) ──depends on──▶ Modular filter structure
         │
         ▼
Project 3 (AWS ECS) ──depends on──▶ Assembled config files
```

**Recommended Implementation Order:**
1. **Project 1** first - Creates the modular structure needed by other projects
2. **Project 2** second - Builds on modular filters, creates CIM output
3. **Project 3** third - Can use any assembled config (legacy or CIM)

Projects 2 and 3 can be developed in parallel after Project 1 is complete.

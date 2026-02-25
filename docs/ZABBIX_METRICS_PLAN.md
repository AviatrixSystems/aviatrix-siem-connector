# Zabbix Trapper Output — Integration Plan

## Overview

Add Zabbix as an output destination for the Aviatrix Log Integration Engine, using the **Zabbix Sender/Trapper protocol** to push parsed gateway metrics and log events into Zabbix trapper items. This follows the same modular pattern as the existing Splunk HEC, Azure Log Analytics, and Dynatrace Metrics outputs.

Unlike Dynatrace (which uses a metrics-only line protocol) or Splunk (which accepts arbitrary JSON events), Zabbix requires **pre-defined items on pre-defined hosts**. This fundamentally shapes the integration design: every metric key must correspond to a trapper item already configured in Zabbix, and every gateway must exist as a Zabbix host.

---

## Zabbix Data Model — Key Concepts

### Hosts

A Zabbix host represents a monitored entity. Each Aviatrix gateway maps to one Zabbix host. The **technical host name** (not the visible/display name) is used in the sender protocol and must match exactly.

Two approaches for host provisioning:

1. **Manual/Template-based** — Admin creates hosts in Zabbix and links the Aviatrix template. Simple, explicit, but doesn't scale.
2. **Low-Level Discovery (LLD)** — The engine sends discovery data that auto-creates items from prototypes. Scales well but adds complexity.

**Recommendation:** Start with approach 1 (manual + template). Provide an importable Zabbix template XML that pre-defines all trapper items. Document LLD as a future enhancement for auto-discovery of gateways and interfaces.

### Items

A Zabbix item is a single data point collected for a host. Each item has:

- **Key** — unique identifier within a host (max 255 chars)
- **Type** — must be "Zabbix trapper" to accept pushed data
- **Type of information** — Numeric (float), Numeric (unsigned), Character, Text, or Log
- **Allowed hosts** — IP allowlist for who can push data (optional but recommended)

### Templates

A Zabbix template is a reusable set of items, triggers, graphs, and discovery rules. We'll provide a template that users import into Zabbix and link to their gateway hosts.

---

## Sender Protocol

### Request Format

```json
{
  "request": "sender data",
  "data": [
    {
      "host": "gw-k8s-transit",
      "key": "aviatrix.cpu.idle",
      "value": "95.2",
      "clock": 1739462365,
      "ns": 107000000
    },
    {
      "host": "gw-k8s-transit",
      "key": "aviatrix.memory.used",
      "value": "1104320000",
      "clock": 1739462365,
      "ns": 107000000
    }
  ],
  "clock": 1739462366,
  "ns": 0
}
```

### Response Format

```json
{
  "response": "success",
  "info": "processed: 2; failed: 0; total: 2; seconds spent: 0.003"
}
```

### Protocol Details

| Property | Value |
|----------|-------|
| Transport | TCP to Zabbix server/proxy port **10051** |
| Framing | `ZBXD\x01` header + 8-byte little-endian payload length + JSON |
| Batching | Multiple items per request (all items in `data` array) |
| Timestamps | Unix epoch seconds (`clock`) + optional nanoseconds (`ns`) |
| Values | Always strings — Zabbix casts based on item's "Type of information" |
| Authentication | IP-based (`Allowed hosts` on trapper items) — no token/password |
| Encryption | TLS optional (configured on Zabbix server side) |

### Key Differences from Dynatrace

| Aspect | Dynatrace MINT | Zabbix Sender |
|--------|---------------|---------------|
| Protocol | HTTP POST (text/plain) | TCP binary-framed JSON |
| Auth | API token (Bearer) | IP allowlist |
| Metric registration | Auto-created on first ingest | Must pre-exist as trapper items |
| Dimensions | Inline key=value pairs | Encoded in item key or separate items |
| Batching | Multiple lines per POST | Multiple items per TCP message |
| Host concept | Optional (`dt.entity.host` dim) | Required — every value needs a host |
| Timestamps | Milliseconds UTC | Seconds + nanoseconds |

---

## Item Key Design

### Naming Convention

Zabbix item keys use a different convention than Dynatrace metric keys. Where Dynatrace uses dots freely (`aviatrix.gateway.cpu.idle`), Zabbix conventionally uses dots for hierarchy and **square brackets for parameters** that vary per instance (like interface name or core index).

```
aviatrix.cpu.idle              — aggregate CPU idle for the gateway
aviatrix.cpu.idle[0]           — CPU idle for core 0
aviatrix.cpu.idle[1]           — CPU idle for core 1
aviatrix.net.bytes_rx[eth0]    — RX bytes/s on eth0
aviatrix.net.conntrack[eth0]   — conntrack count on eth0
```

The `gateway` namespace level from Dynatrace is dropped — in Zabbix, the host itself *is* the gateway, so `aviatrix.gateway.cpu.idle` is redundant. The host carries the gateway identity.

### Item Key Rules

- Max length: **255 characters**
- Allowed in key name: `a-z`, `A-Z`, `0-9`, `_`, `-`, `.`
- Parameters in square brackets: `key[param1,param2]`
- Parameters: quoted strings, unquoted strings, or arrays
- No macro expansion in trapper item keys
- Key must be unique within a host

### Full Item Inventory

#### System Stats (from `gw_sys_stats` events)

| Item Key | Type of Info | Units | Source | Description |
|----------|-------------|-------|--------|-------------|
| `aviatrix.cpu.idle` | Numeric (float) | % | `cpu_idle` direct | CPU idle percentage (aggregate) |
| `aviatrix.cpu.usage` | Numeric (float) | % | `100 - cpu_idle` | CPU usage percentage (aggregate) |
| `aviatrix.cpu.idle[{#CORE}]` | Numeric (float) | % | `100 - busy_avg` | Per-core CPU idle (LLD prototype) |
| `aviatrix.cpu.usage[{#CORE}]` | Numeric (float) | % | `busy_avg` | Per-core CPU usage (LLD prototype) |
| `aviatrix.memory.available` | Numeric (unsigned) | B | `memory_available * 1024` | Available memory in bytes |
| `aviatrix.memory.total` | Numeric (unsigned) | B | `memory_total * 1024` | Total memory in bytes |
| `aviatrix.memory.free` | Numeric (unsigned) | B | `memory_free * 1024` | Free memory in bytes |
| `aviatrix.memory.used` | Numeric (unsigned) | B | `(total - available) * 1024` | Used memory in bytes |
| `aviatrix.memory.usage` | Numeric (float) | % | `(1 - avail/total) * 100` | Memory usage percentage |
| `aviatrix.disk.available` | Numeric (unsigned) | B | `disk_free * 1024` | Available disk in bytes |
| `aviatrix.disk.total` | Numeric (unsigned) | B | `disk_total * 1024` | Total disk in bytes |
| `aviatrix.disk.used` | Numeric (unsigned) | B | `(total - free) * 1024` | Used disk in bytes |
| `aviatrix.disk.usage` | Numeric (float) | % | `(1 - free/total) * 100` | Disk usage percentage |

**Per-core CPU:** In the manual/template approach, define items for cores 0-7 (covering most instance types). With LLD, the engine sends discovery data listing available cores, and Zabbix auto-creates items from the `aviatrix.cpu.idle[{#CORE}]` prototype.

#### Network Stats (from `gw_net_stats` events)

| Item Key | Type of Info | Units | Source | Description |
|----------|-------------|-------|--------|-------------|
| `aviatrix.net.bytes_rx[{#IFACE}]` | Numeric (float) | Bps | `parse_to_bytes(raw_rx_rate)` | RX rate in bytes/sec |
| `aviatrix.net.bytes_tx[{#IFACE}]` | Numeric (float) | Bps | `parse_to_bytes(raw_tx_rate)` | TX rate in bytes/sec |
| `aviatrix.net.bytes_total[{#IFACE}]` | Numeric (float) | Bps | `parse_to_bytes(raw_rxtx_rate)` | Total rate in bytes/sec |
| `aviatrix.net.rx_cumulative[{#IFACE}]` | Numeric (unsigned) | B | `parse_to_bytes(raw_rx_cum)` | Cumulative RX bytes |
| `aviatrix.net.tx_cumulative[{#IFACE}]` | Numeric (unsigned) | B | `parse_to_bytes(raw_tx_cum)` | Cumulative TX bytes |
| `aviatrix.net.rxtx_cumulative[{#IFACE}]` | Numeric (unsigned) | B | `parse_to_bytes(raw_rxtx_cum)` | Cumulative RX+TX bytes |
| `aviatrix.net.conntrack.count[{#IFACE}]` | Numeric (unsigned) | — | direct | Current conntrack entries |
| `aviatrix.net.conntrack.available[{#IFACE}]` | Numeric (unsigned) | — | direct | Conntrack entries available |
| `aviatrix.net.conntrack.usage[{#IFACE}]` | Numeric (float) | % | `rate * 100` | Conntrack usage percentage |
| `aviatrix.net.conntrack_limit_exceeded[{#IFACE}]` | Numeric (unsigned) | — | direct | Cumulative conntrack limit exceeded count |
| `aviatrix.net.bw_in_limit_exceeded[{#IFACE}]` | Numeric (unsigned) | — | direct | Cumulative inbound BW limit exceeded |
| `aviatrix.net.bw_out_limit_exceeded[{#IFACE}]` | Numeric (unsigned) | — | direct | Cumulative outbound BW limit exceeded |
| `aviatrix.net.pps_limit_exceeded[{#IFACE}]` | Numeric (unsigned) | — | direct | Cumulative PPS limit exceeded |
| `aviatrix.net.linklocal_limit_exceeded[{#IFACE}]` | Numeric (unsigned) | — | direct | Cumulative linklocal limit exceeded |

**Interface parameter:** Most gateways have only `eth0`, but the bracket parameter keeps it extensible. In the non-LLD template, define items with `[eth0]`. With LLD, auto-discover interfaces.

#### Security/Log Events (from other log types)

| Item Key | Type of Info | Source Tag | Description |
|----------|-------------|-----------|-------------|
| `aviatrix.fqdn.event` | Text | `fqdn` | FQDN firewall rule event (JSON) |
| `aviatrix.cmd.event` | Text | `cmd` | Controller API command event (JSON) |
| `aviatrix.microseg.event` | Text | `microseg` | L4 microsegmentation event (JSON) |
| `aviatrix.mitm.event` | Text | `mitm` | L7/TLS inspection event (JSON) |
| `aviatrix.suricata.event` | Text | `suricata` | Suricata IDS alert event (JSON) |
| `aviatrix.tunnel.event` | Text | `tunnel_status` | Tunnel status change event (JSON) |

**Design decision:** Security/log events are sent as JSON text to a single trapper item per log type. This keeps the Zabbix item count manageable. Zabbix preprocessing (JSONPath) can extract specific fields for triggers if needed. The alternative — one item per field — would explode the item count and is impractical for variable-schema events like Suricata alerts.

### Host Naming Convention

The Zabbix host technical name must match what the engine sends. Two options:

1. **Use gateway name directly:** `k8s-transit`, `prod-spoke-01`
   - Pros: Simple, matches what operators already know
   - Cons: May conflict with existing Zabbix hosts if the same name is used elsewhere

2. **Use a prefix:** `avx-k8s-transit`, `avx-prod-spoke-01`
   - Pros: Namespace isolation, easy to identify Aviatrix hosts
   - Cons: Extra config step for users

**Recommendation:** Make the prefix configurable via `ZABBIX_HOST_PREFIX` env var (default: empty string = no prefix). Document both approaches.

For controller events (CMD/API logs), use the controller hostname `Controller-<ip>` as the Zabbix host.

---

## Logstash Output Architecture

### Option A: logstash-output-zabbix Plugin (Recommended)

Use the existing [logstash-output-zabbix](https://github.com/logstash-plugins/logstash-output-zabbix) plugin with `multi_value` mode.

#### How It Works

The plugin implements the Zabbix Sender binary protocol directly. With `multi_value`, it sends multiple key/value pairs from a single Logstash event in one TCP message to the Zabbix server.

#### Configuration Pattern

```ruby
output {
    if ("gw_sys_stats" in [tags] or "gw_net_stats" in [tags]) and
       ("${LOG_PROFILE:all}" == "all" or "${LOG_PROFILE:all}" == "networking") {
        zabbix {
            id => "zabbix-metrics"
            zabbix_server_host => "${ZABBIX_SERVER}"
            zabbix_server_port => "${ZABBIX_PORT:10051}"
            zabbix_host => "[@metadata][zabbix_host]"
            multi_value => [
                "[@metadata][zabbix_keys][0]", "[@metadata][zabbix_values][0]",
                "[@metadata][zabbix_keys][1]", "[@metadata][zabbix_values][1]",
                # ... dynamically built in Ruby filter
            ]
            timeout => 5
        }
    }
}
```

#### Problem: multi_value Is Static

The `multi_value` array is defined at config parse time — you can't dynamically vary how many key/value pairs are sent per event. A `gw_sys_stats` event has ~13 metrics; a `gw_net_stats` event has ~14; per-core CPU varies by instance type.

**Workarounds:**

1. **Fixed maximum slots:** Define enough `multi_value` pairs to cover the maximum case (e.g., 30 slots for net_stats + 8-core CPU). The plugin silently skips pairs where the referenced field doesn't exist. Wasteful but functional.

2. **Build a single JSON value per event type:** Instead of multi_value, send one key/value pair where the value is a JSON blob. The Zabbix item uses "Dependent items" + JSONPath preprocessing to fan out into individual metrics. This is the modern Zabbix pattern.

3. **Use a custom Ruby output instead of the plugin:** Implement the Zabbix Sender protocol directly in a Ruby filter/output, building the exact payload needed per event. Full control, no plugin dependency.

### Option B: Custom Ruby Output (Alternative)

Bypass the logstash-output-zabbix plugin entirely. Build the Zabbix Sender JSON payload in a Ruby filter, then send it via a raw TCP output or embedded Ruby socket.

```ruby
filter {
    if "gw_sys_stats" in [tags] {
        ruby {
            id => "zabbix-build-sys-stats"
            code => '
                gw = event.get("gateway") || "unknown"
                prefix = ENV.fetch("ZABBIX_HOST_PREFIX", "")
                zabbix_host = "#{prefix}#{gw}"
                ts = event.get("@timestamp").to_i

                items = []

                cpu_idle = event.get("cpu_idle")
                if cpu_idle
                    idle_f = cpu_idle.to_f
                    items << { "host" => zabbix_host, "key" => "aviatrix.cpu.idle",
                               "value" => idle_f.to_s, "clock" => ts }
                    items << { "host" => zabbix_host, "key" => "aviatrix.cpu.usage",
                               "value" => (100 - idle_f).round(2).to_s, "clock" => ts }
                end

                # Memory (raw values are kB)
                mem_avail = event.get("memory_available")
                mem_total = event.get("memory_total")
                mem_free  = event.get("memory_free")
                if mem_avail && mem_total
                    avail_b = mem_avail.to_f * 1024
                    total_b = mem_total.to_f * 1024
                    free_b  = mem_free.to_f * 1024
                    items << { "host" => zabbix_host, "key" => "aviatrix.memory.available",
                               "value" => avail_b.to_i.to_s, "clock" => ts }
                    items << { "host" => zabbix_host, "key" => "aviatrix.memory.total",
                               "value" => total_b.to_i.to_s, "clock" => ts }
                    items << { "host" => zabbix_host, "key" => "aviatrix.memory.free",
                               "value" => free_b.to_i.to_s, "clock" => ts }
                    items << { "host" => zabbix_host, "key" => "aviatrix.memory.used",
                               "value" => (total_b - avail_b).to_i.to_s, "clock" => ts }
                    if total_b > 0
                        items << { "host" => zabbix_host, "key" => "aviatrix.memory.usage",
                                   "value" => ((1.0 - avail_b / total_b) * 100).round(2).to_s, "clock" => ts }
                    end
                end

                # Disk (raw values are kB)
                disk_total = event.get("disk_total")
                disk_free  = event.get("disk_free")
                if disk_total && disk_free
                    dt_b = disk_total.to_f * 1024
                    df_b = disk_free.to_f * 1024
                    items << { "host" => zabbix_host, "key" => "aviatrix.disk.available",
                               "value" => df_b.to_i.to_s, "clock" => ts }
                    items << { "host" => zabbix_host, "key" => "aviatrix.disk.total",
                               "value" => dt_b.to_i.to_s, "clock" => ts }
                    items << { "host" => zabbix_host, "key" => "aviatrix.disk.used",
                               "value" => (dt_b - df_b).to_i.to_s, "clock" => ts }
                    if dt_b > 0
                        items << { "host" => zabbix_host, "key" => "aviatrix.disk.usage",
                                   "value" => ((1.0 - df_b / dt_b) * 100).round(2).to_s, "clock" => ts }
                    end
                end

                # Per-core CPU
                cpu_cores = event.get("cpu_cores_parsed")
                if cpu_cores.is_a?(Array)
                    cpu_cores.each do |core|
                        name = core["name"]
                        next unless name && name != "-1"
                        busy = core["busy_avg"]
                        next unless busy
                        busy_f = busy.to_f
                        items << { "host" => zabbix_host, "key" => "aviatrix.cpu.idle[#{name}]",
                                   "value" => (100 - busy_f).round(2).to_s, "clock" => ts }
                        items << { "host" => zabbix_host, "key" => "aviatrix.cpu.usage[#{name}]",
                                   "value" => busy_f.to_s, "clock" => ts }
                    end
                end

                event.set("[@metadata][zabbix_sender_items]", items) unless items.empty?
            '
        }
    }
}
```

Then send via a custom Ruby output that opens a TCP socket to the Zabbix server and frames the JSON per the ZBXD protocol.

**Pros:** Full control over batching, error handling, retries. No plugin dependency.
**Cons:** Must implement binary framing (`ZBXD\x01` + length header). More code to maintain.

### Option C: Dependent Items Pattern (Recommended for Modern Zabbix 6.0+)

Instead of sending 13+ individual trapper items per event, send **one JSON blob per event type** to a single "master" trapper item, then use Zabbix **dependent items** with JSONPath preprocessing to fan out.

#### How It Works

1. Engine sends one value to `aviatrix.sys_stats.raw` containing the full JSON payload
2. Zabbix master item receives it
3. Dependent items (defined in the template) extract individual metrics:
   - `aviatrix.cpu.idle` ← JSONPath: `$.cpu_idle`
   - `aviatrix.memory.used` ← JSONPath: `$.memory_used`
   - etc.

#### Advantages

- **Minimal sender complexity:** One key/value pair per event instead of 13+
- **Item management in Zabbix:** Adding/removing derived metrics is a Zabbix template change, not a Logstash config change
- **Preprocessing power:** Zabbix can apply change-per-second, custom multipliers, JSONPath, JavaScript — right in the item definition
- **Network efficiency:** One TCP send per event instead of many

#### Item Structure

```
aviatrix.sys_stats.raw          ← Master trapper item (Text type, stores JSON)
  ├── aviatrix.cpu.idle         ← Dependent, JSONPath $.cpu_idle
  ├── aviatrix.cpu.usage        ← Dependent, JSONPath $.cpu_usage (or custom JS: 100 - value)
  ├── aviatrix.memory.available ← Dependent, JSONPath $.memory_available, preprocessing ×1024
  ├── aviatrix.memory.total     ← Dependent, JSONPath $.memory_total, preprocessing ×1024
  ├── ...
  └── aviatrix.disk.usage       ← Dependent, custom JS preprocessing

aviatrix.net_stats.raw          ← Master trapper item (Text type, stores JSON)
  ├── aviatrix.net.bytes_rx[eth0]    ← Dependent, JSONPath $.bytes_rx
  ├── aviatrix.net.conntrack.count[eth0] ← Dependent, JSONPath $.conntrack_count
  ├── ...
  └── aviatrix.net.pps_limit_exceeded[eth0] ← Dependent, JSONPath $.pps_limit_exceeded

aviatrix.log.raw[fqdn]         ← Master trapper item per log type
aviatrix.log.raw[microseg]     ← etc.
aviatrix.log.raw[suricata]
aviatrix.log.raw[cmd]
aviatrix.log.raw[mitm]
aviatrix.log.raw[tunnel_status]
```

---

## Recommended Approach

**Use Option C (Dependent Items)** with the **logstash-output-zabbix plugin** for transport.

This gives us:

1. **Simple Logstash config** — build one JSON blob per event type, send as one key/value
2. **Existing plugin** — no custom TCP implementation needed
3. **Zabbix-native preprocessing** — unit conversions, derived metrics, and field extraction happen in the Zabbix template
4. **Template portability** — users import the template and get all items, triggers, and graphs automatically
5. **Extensibility** — adding a new derived metric is a template change, not a Logstash change

### What the Engine Sends (Per Event Type)

#### gw_sys_stats → `aviatrix.sys_stats.raw`

```json
{
    "gateway": "k8s-transit",
    "alias": "k8s-transit",
    "cpu_idle": 95.2,
    "cpu_usage": 4.8,
    "memory_available": 6925107200,
    "memory_total": 8056954880,
    "memory_free": 5905580032,
    "memory_used": 1131847680,
    "memory_usage": 14.03,
    "disk_available": 59338998784,
    "disk_total": 67232813056,
    "disk_used": 7893814272,
    "disk_usage": 11.74,
    "cpu_cores": [
        {"core": "0", "idle": 97.2, "usage": 2.8},
        {"core": "1", "idle": 88.4, "usage": 11.6},
        {"core": "2", "idle": 93.1, "usage": 6.9},
        {"core": "3", "idle": 91.6, "usage": 8.4}
    ],
    "timestamp": 1739462365
}
```

#### gw_net_stats → `aviatrix.net_stats.raw`

```json
{
    "gateway": "k8s-demo-db",
    "alias": "k8s-demo-db",
    "interface": "eth0",
    "public_ip": "3.12.42.129",
    "private_ip": "10.5.0.39",
    "bytes_rx": 55367.68,
    "bytes_tx": 129882.11,
    "bytes_total_rate": 185249.79,
    "rx_cumulative": 2673066803,
    "tx_cumulative": 534958489,
    "rxtx_cumulative": 3208025292,
    "conntrack_count": 45,
    "conntrack_available": 51294,
    "conntrack_usage": 0.09,
    "conntrack_limit_exceeded": 0,
    "bw_in_limit_exceeded": 5445,
    "bw_out_limit_exceeded": 54,
    "pps_limit_exceeded": 4424,
    "linklocal_limit_exceeded": 0,
    "timestamp": 1739462365
}
```

#### Security/log events → `aviatrix.log.raw[<tag>]`

Send the parsed event fields as JSON. The Zabbix template can define dependent items for commonly-triggered fields (e.g., extract `action` from microseg events for trigger evaluation).

### What Goes in the Zabbix Template

The template XML defines:

1. **Master trapper items:** `aviatrix.sys_stats.raw`, `aviatrix.net_stats.raw`, `aviatrix.log.raw[fqdn]`, etc.
2. **Dependent items with preprocessing:** JSONPath extraction + multipliers for each derived metric
3. **Triggers:** CPU > 90%, memory > 85%, disk > 90%, tunnel state changes, IDS alerts
4. **Graphs:** CPU usage over time, memory usage, network throughput, conntrack usage
5. **LLD rules (optional):** Discovery of CPU cores and network interfaces via trapper-type discovery

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ZABBIX_SERVER` | Yes | — | Zabbix server/proxy hostname or IP |
| `ZABBIX_PORT` | No | `10051` | Zabbix trapper port |
| `ZABBIX_HOST_PREFIX` | No | `""` | Prefix for Zabbix host names (e.g., `avx-`) |
| `ZABBIX_SOURCE` | No | `aviatrix` | Source identifier added to JSON payloads |
| `LOG_PROFILE` | No | `all` | Which log types to forward: `all`, `networking`, `security` |

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `outputs/zabbix/output.conf` | **NEW** | Ruby filter to build JSON payloads + zabbix output block |
| `outputs/zabbix/README.md` | **NEW** | Setup guide: template import, host creation, env vars, testing |
| `outputs/zabbix/template/aviatrix_template.xml` | **NEW** | Importable Zabbix template with all items, triggers, graphs |
| `outputs/zabbix/docker_run.tftpl` | **NEW** | Docker run template with Zabbix env vars |
| `filters/94-save-raw-net-rates.conf` | **MODIFY** | Add `ZABBIX_SERVER` env var gate alongside existing `DT_METRICS_URL` gate |
| `test-tools/validate-zabbix-output.py` | **NEW** | Validates JSON payload structure, key names, value types |

### Filter 94 Modification

The existing filter only preserves raw rate strings when `DT_METRICS_URL` is set. For Zabbix, we also need the raw strings to compute byte values. Extend the condition:

```ruby
# Current
if "gw_net_stats" in [tags] and "${DT_METRICS_URL:}" != ""

# Updated
if "gw_net_stats" in [tags] and ("${DT_METRICS_URL:}" != "" or "${ZABBIX_SERVER:}" != "")
```

---

## Comparison: Dynatrace vs Zabbix Metric Naming

| Dynatrace Metric Key | Zabbix Item Key | Notes |
|-----------------------|-----------------|-------|
| `aviatrix.gateway.cpu.idle` | `aviatrix.cpu.idle` | No `gateway` namespace — host IS the gateway |
| `aviatrix.gateway.cpu.idle` (core="0") | `aviatrix.cpu.idle[0]` | Zabbix uses bracket params for dimensions |
| `aviatrix.gateway.memory.avail` | `aviatrix.memory.available` | Spelled out for clarity |
| `aviatrix.gateway.memory.usage` | `aviatrix.memory.usage` | Same concept |
| `aviatrix.gateway.disk.used.percent` | `aviatrix.disk.usage` | Simplified — "usage" is the Zabbix convention for % |
| `aviatrix.gateway.net.bytes_rx` (interface dim) | `aviatrix.net.bytes_rx[eth0]` | Interface in brackets |
| `aviatrix.gateway.net.conntrack.count` | `aviatrix.net.conntrack.count[eth0]` | Interface in brackets |
| `aviatrix.gateway.net.bw_in_limit_exceeded` | `aviatrix.net.bw_in_limit_exceeded[eth0]` | Interface in brackets |

---

## Batching & Performance

### Current Architecture (One Event = One TCP Send)

The logstash-output-zabbix plugin sends one TCP message per Logstash event. With the dependent items approach, each event produces exactly one key/value pair, so this is fine — each TCP message contains one trapper item.

At 100 gateways reporting every 40 seconds:
- 100 gw × 2 event types (sys + net) = 200 events/40s = **5 TCP sends/second**
- Plus security events: variable, but typically < 100/second even under load

This is well within Zabbix server capacity. The trapper process is lightweight.

### Future Optimization: Batch Multiple Events

If scaling to 1000+ gateways, the custom Ruby output (Option B) can accumulate items from multiple events into a single TCP message. The Zabbix protocol supports this natively — just add more entries to the `data` array.

---

## Trigger Examples (for Template)

```
# High CPU usage
{aviatrix.cpu.usage.last()} > 90 for 5m

# Memory pressure
{aviatrix.memory.usage.last()} > 85

# Disk space critical
{aviatrix.disk.usage.last()} > 90

# Tunnel state change (from log event)
{aviatrix.log.raw[tunnel_status].str("new_state\":\"Down")} = 1

# IDS alert detected
{aviatrix.log.raw[suricata].nodata(300)} = 0 and
{aviatrix.log.raw[suricata].str("severity\":1")} = 1
```

---

## Testing Workflow

```bash
# 1. Assemble config
cd logstash-configs && ./scripts/assemble-config.sh zabbix

# 2. Start a mock Zabbix trapper (netcat or custom script)
cd test-tools && python mock-zabbix-trapper.py --port 10051

# 3. Run Logstash
docker run --rm \
  -v $(pwd)/assembled:/config \
  -v $(pwd)/patterns:/usr/share/logstash/patterns \
  -e ZABBIX_SERVER=host.docker.internal \
  -e ZABBIX_PORT=10051 \
  -e ZABBIX_HOST_PREFIX="" \
  -e ZABBIX_SOURCE=aviatrix \
  -e LOG_PROFILE=all \
  -e XPACK_MONITORING_ENABLED=false \
  -p 5002:5000 -p 5002:5000/udp \
  docker.elastic.co/logstash/logstash:8.16.2 \
  logstash -f /config/zabbix-full.conf

# 4. Stream test logs
cd test-tools/sample-logs
./stream-logs.py --port 5002 --filter netstats -v
./stream-logs.py --port 5002 --filter sysstats -v

# 5. Validate captured output
python test-tools/validate-zabbix-output.py captured-output.json
```

---

## Open Questions

1. **Plugin vs custom Ruby output:** The logstash-output-zabbix plugin is unmaintained (last release ~2018). It works, but for the dependent items pattern (one key/value per event), even a simple `ruby {}` output block with a TCP socket would suffice. Should we avoid the plugin dependency?

2. **LLD for gateway auto-discovery:** Should the engine also send Zabbix LLD discovery data so that gateways auto-register as hosts? This would require a "discovery" trapper item and a host prototype in the template. Powerful but adds complexity.

3. **Zabbix proxy support:** Many Zabbix deployments route trapper data through proxies. The plugin's `zabbix_server_host` can point to a proxy, but should we document this explicitly or add a separate env var?

4. **Log event granularity:** For security events, should we send the full JSON blob to one master item (simpler), or should we extract key fields (action, src_ip, dst_ip, severity) into individual items for direct triggering (more trigger flexibility)?

5. **Template format:** Zabbix 6.0+ supports YAML template export in addition to XML. Should we provide both formats?

---

## Implementation Order

1. **Filter 94 modification** — extend env var gate for `ZABBIX_SERVER`
2. **Ruby filter for JSON payload building** — `gw_sys_stats` and `gw_net_stats` builders
3. **Output block** — logstash-output-zabbix or custom Ruby TCP
4. **Zabbix template XML** — master items, dependent items, triggers, graphs
5. **Mock trapper for testing** — Python script that accepts ZBXD protocol
6. **Validation script** — verify JSON payloads against expected schema
7. **Documentation** — README with setup guide, env vars, troubleshooting

---

## Key Documentation Links

- [Zabbix Sender Protocol](https://www.zabbix.com/documentation/current/en/manual/appendix/protocols/zabbix_sender)
- [Trapper Items](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/trapper)
- [Item Key Format](https://www.zabbix.com/documentation/current/en/manual/config/items/item/key)
- [Low-Level Discovery](https://www.zabbix.com/documentation/current/en/manual/discovery/low_level_discovery)
- [Dependent Items](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/dependent_items)
- [logstash-output-zabbix Plugin](https://github.com/logstash-plugins/logstash-output-zabbix)
- [Logstash Zabbix Output Docs](https://www.elastic.co/guide/en/logstash/8.19/plugins-outputs-zabbix.html)
- [Python zabbix_utils Sender](https://www.zabbix.com/documentation/current/en/devel/python/sender)

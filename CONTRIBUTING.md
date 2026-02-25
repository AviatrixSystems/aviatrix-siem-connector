# Contributing

This guide covers how to develop, test, and validate changes to the SIEM Connector.

## Prerequisites

- Docker Desktop (for running Logstash locally)
- Python 3.6+ (for test tooling)
- AWS CLI (for Splunk end-to-end tests, optional)

## Development Workflow

### 1. Make Your Changes

Edit the relevant files in `logstash-configs/`:

- **Filters** (`filters/`): Numbered for execution order. The number prefix determines processing sequence.
- **Outputs** (`outputs/<type>/output.conf`): Destination-specific routing and formatting.
- **Patterns** (`patterns/avx.conf`): Custom grok patterns shared across all filters.

### 2. Assemble the Config

After editing modular files, assemble a complete config for testing:

```bash
cd logstash-configs
./scripts/assemble-config.sh splunk-hec           # or azure-log-ingestion, webhook-test
```

This concatenates inputs + filters + output into `assembled/<type>-full.conf`.

### 3. Validate Syntax

```bash
cd logstash-configs
docker run --rm \
  -v "$(pwd)/assembled:/config" \
  -v "$(pwd)/patterns:/usr/share/logstash/patterns" \
  -e SPLUNK_ADDRESS=http://localhost -e SPLUNK_PORT=8088 \
  -e SPLUNK_HEC_AUTH=dummy -e FLATTEN_SURICATA=true \
  docker.elastic.co/logstash/logstash:8.16.2 \
  logstash -f /config/splunk-hec-full.conf --config.test_and_exit
```

Environment variables must be set (even as dummies) or Logstash will fail to parse the config.

### 4. Test with Webhook Viewer (Local Functional Test)

This is the primary development test loop. It lets you inspect every parsed event without needing a Splunk instance.

**Terminal 1 - Start webhook viewer:**
```bash
cd test-tools/webhook-viewer/local && ./run.sh
```
Access the UI at http://localhost:8080. Click "New URL" then "Create" to get a webhook endpoint URL.

**Terminal 2 - Run Logstash:**
```bash
cd logstash-configs
./scripts/assemble-config.sh webhook-test

docker run --rm --name logstash-webhook-test \
  -p 5002:5000/udp -p 5002:5000/tcp \
  -v "$(pwd)/assembled:/config" \
  -v "$(pwd)/patterns:/usr/share/logstash/patterns" \
  -e WEBHOOK_URL=http://host.docker.internal:8080/<your-session-id> \
  -e FLATTEN_SURICATA=true \
  docker.elastic.co/logstash/logstash:8.16.2 \
  logstash -f /config/webhook-test-full.conf
```

**Terminal 3 - Stream test logs:**
```bash
cd test-tools/sample-logs
./generate-current-samples.sh --overwrite   # Refresh timestamps to now
python3 stream-logs.py --port 5002 -v       # Stream all log types
```

**What to check in the webhook viewer:**
- All log types parsed (no `_grokparsefailure` tags)
- Fields extracted correctly for each event type
- JSON structures (like `cpu_cores_parsed`) serialize as proper arrays/objects
- `time` field is a recent unix epoch (not null, not zero)
- No `%{fieldname}` literal strings in the output (indicates unresolved Logstash variables)

**Expected output:** 38 events from 40 input lines (1 suricata `Notice` log is dropped by the filter, 1 legacy microseg format is throttled).

### 5. End-to-End Splunk Test (Optional)

For changes to Splunk HEC output, validate against a real Splunk instance:

```bash
cd logstash-configs
./scripts/assemble-config.sh splunk-hec

docker run --rm --name logstash-splunk-test \
  -p 5002:5000/udp -p 5002:5000/tcp \
  -v "$(pwd)/assembled:/config" \
  -v "$(pwd)/patterns:/usr/share/logstash/patterns" \
  -e SPLUNK_ADDRESS=https://<splunk-ip> \
  -e SPLUNK_PORT=8088 \
  -e SPLUNK_HEC_AUTH=<hec-token> \
  -e FLATTEN_SURICATA=true \
  -e LOG_PROFILE=all \
  docker.elastic.co/logstash/logstash:8.16.2 \
  logstash -f /config/splunk-hec-full.conf
```

Then stream test logs and verify in Splunk:
```
index=* sourcetype=aviatrix:* | stats count by sourcetype
```

## Adding a New Log Type

1. **Create a filter file** named `filters/1X-<type>.conf` (choose a number that places it before the throttle/timestamp filters at 80+).

2. **Add grok patterns** that:
   - Match only the new log type (use the exclusion pattern: `if !("tag1" in [tags] or "tag2" in [tags])`)
   - Extract `SYSLOG_TIMESTAMP:date` from the syslog header (required for timestamp normalization)
   - Add a unique tag (e.g., `add_tag => ["my_new_type"]`)
   - Set `tag_on_failure => []` to avoid polluting other log types with `_grokparsefailure`

3. **Add output blocks** in each output type (`splunk-hec/output.conf`, `webhook-test/output.conf`, etc.) with the appropriate tag condition.

4. **Add test samples** to `test-tools/sample-logs/test-samples.log` with a section comment header.

5. **Test** using the webhook viewer workflow above.

## Adding a New Output Type

1. Create `outputs/<new-type>/output.conf` with the output block.
2. **Implement `LOG_PROFILE` filtering** on each output block (see Log Profiles below).
3. Run `./scripts/assemble-config.sh <new-type>` to generate the full config.
4. Test with `--config.test_and_exit` for syntax, then functionally test with sample logs.

## Log Profiles

All output types should support the `LOG_PROFILE` environment variable for selective log forwarding. This is a preferred architectural pattern — not every output needs every log type, and customers use profiles to control SIEM ingestion costs.

### Standard Profiles

| Profile | Log Types | Use Case |
|---------|-----------|----------|
| `all` (default) | All 8 log types | Full visibility |
| `security` | fqdn, cmd, microseg, mitm, suricata | Firewall, IDS/IPS, audit — SIEM/SOC |
| `networking` | gw_net_stats, gw_sys_stats, tunnel_status | Gateway health, performance, availability — NOC/observability |

### Log Type to Profile Mapping

| Tag | Profile |
|-----|---------|
| `fqdn` | security |
| `cmd` | security |
| `microseg` | security |
| `mitm` | security |
| `suricata` | security |
| `gw_net_stats` | networking |
| `gw_sys_stats` | networking |
| `tunnel_status` | networking |

### Implementation Pattern

Gate each output block on both the event tag and the `LOG_PROFILE` environment variable:

```ruby
output {
    # Security logs — gate on "security" profile
    if "suricata" in [tags] and ("${LOG_PROFILE:all}" == "all" or "${LOG_PROFILE:all}" == "security") {
        # ...
    }

    # Networking logs — gate on "networking" profile
    else if "gw_net_stats" in [tags] and ("${LOG_PROFILE:all}" == "all" or "${LOG_PROFILE:all}" == "networking") {
        # ...
    }
}
```

The `${LOG_PROFILE:all}` syntax defaults to `all` when the variable is unset, ensuring backward compatibility. An output that only handles a subset of log types (e.g., Dynatrace only consumes `networking` logs) still benefits from supporting the profile variable for consistency.

## Filter Ordering

Filters are processed in filename sort order. The numbering scheme:

| Range | Purpose | Examples |
|-------|---------|---------|
| 10-19 | Log type parsing (grok + field extraction) | `10-fqdn`, `11-cmd`, `14-suricata`, `17-cpu-cores-parse` |
| 80-89 | Throttling / rate limiting | `80-throttle` |
| 90-94 | Timestamp normalization | `90-timestamp` (parses `date` field, sets `unix_time`) |
| 95-99 | Post-processing (type coercions, HEC builders) | `95-field-conversion`, `96-sys-stats-hec` |

**Key rule:** Any filter that depends on `unix_time` or type-converted fields **must** be numbered > 95.

## Timestamp Handling

Understanding timestamp flow is critical to avoid events appearing at the wrong time in your SIEM:

1. **Grok patterns** extract `SYSLOG_TIMESTAMP:date` from each log line's syslog header.
2. **`90-timestamp.conf`** parses the `date` field into `@timestamp`, then computes `unix_time = @timestamp.to_i`.
3. **Output configs** use `unix_time` as the HEC `time` field (or equivalent).

**Important:** The `date` filter parses syslog timestamps (`Feb 14 15:04:07`) as **UTC** with no timezone offset. This matches production behavior since Aviatrix gateways and controllers run in UTC.

**Exceptions:**
- **Suricata** (`14-suricata.conf`): Builds its own HEC payload with `unix_time` derived from the suricata JSON timestamp (which includes `+0000` timezone).
- **MITM** (`13-l7-dcf.conf`): Overrides `@timestamp` from the traffic_server JSON unix epoch and removes the `date` field before `90-timestamp.conf` runs.

### Test Sample Timestamps

The file `test-tools/sample-logs/test-samples.log` ships with static timestamps. Before testing, refresh them:

```bash
cd test-tools/sample-logs
./generate-current-samples.sh --overwrite
```

This runs `update-timestamps.py` which rewrites all 9 timestamp formats to a 5-minute window around now (UTC). The script handles: syslog headers, internal slash format, ISO fields, suricata JSON, flow start, JSON unix epochs, nanosecond session_start, cpu_cores protobuf seconds/nanos, and CMD dual timestamps.

## HEC Payload Pattern

For outputs that need complex JSON structures (arrays, nested objects), use the Ruby-built HEC payload pattern instead of Logstash's `format => "json"` mapping:

```ruby
# In a filter (must be numbered > 95 if it needs unix_time):
ruby {
    code => '
        require "json"
        payload = {
            "sourcetype" => "aviatrix:my:type",
            "source" => "avx-my-source",
            "host" => event.get("gateway"),
            "time" => event.get("unix_time"),
            "event" => { ... }  # Can include arrays, nested objects
        }
        event.set("[@metadata][my_hec_payload]", payload.to_json)
    '
}
```

```
# In the output:
http {
    format => "message"
    content_type => "application/json"
    message => "%{[@metadata][my_hec_payload]}"
}
```

This avoids double-escaping issues where Logstash's JSON mapping turns arrays into escaped strings.

Currently used by: **suricata** (`14-suricata.conf`) and **gw_sys_stats** (`96-sys-stats-hec.conf`).

## Docker on macOS

- `--network host` does **not** work on macOS (Docker runs in a VM).
- Use `-p HOST:CONTAINER` port mapping instead.
- Use `host.docker.internal` to reach services on the host from within containers.
- Port 5001 may be occupied by AirPlay Receiver; use 5002 or higher for Logstash.

## Collecting Real Log Samples

When you need real-world log data for testing:

1. Deploy the syslog collector: `cd test-tools/syslog-collector && terraform apply`
2. Point Aviatrix controller syslog to the collector IP on port 514
3. Let logs accumulate, then download via the web UI at `http://<collector-ip>`
4. Add representative samples to `test-samples.log` with section comment headers
5. Tear down: `terraform destroy`

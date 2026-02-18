# Dynatrace Metrics Output

Sends Aviatrix gateway metrics to Dynatrace Metrics Ingest API v2 using the MINT line protocol.

## Prerequisites

1. **Dynatrace Environment** with a metrics ingest endpoint URL
2. **Platform token** (`dt0s16.*`) with `storage:metrics:write` scope
3. **IAM policy** bound to the token's user group granting write permissions

See the [Dynatrace Setup Guide](../../../docs/DYNATRACE_SETUP.md) for step-by-step token, IAM policy, and URL configuration.

## Environment Variables

```bash
# Required
export DT_METRICS_URL="https://<env-id>.apps.dynatrace.com/platform/classic/environment-api/v2/metrics/ingest"
export DT_API_TOKEN="dt0s16.ABC123..."     # Platform token with storage:metrics:write scope

# Optional
export DT_METRIC_SOURCE="aviatrix"          # Source dimension value (default: aviatrix)
export LOG_PROFILE="networking"              # Filter: all (default) or networking
```

## Metrics

### System Statistics (`AviatrixGwSysStats`)

Dimensions: `gateway`, `alias`, `source`

| Metric | Type | Unit | Description |
|--------|------|------|-------------|
| `aviatrix.gateway.cpu.idle` | gauge | Percent | CPU idle % (aggregate) |
| `aviatrix.gateway.cpu.usage` | gauge | Percent | CPU usage % (100 - idle) |
| `aviatrix.gateway.memory.avail` | gauge | Byte | Available memory |
| `aviatrix.gateway.memory.total` | gauge | Byte | Total memory |
| `aviatrix.gateway.memory.free` | gauge | Byte | Free memory |
| `aviatrix.gateway.memory.used` | gauge | Byte | Used memory (total - available) |
| `aviatrix.gateway.memory.usage` | gauge | Percent | Memory utilization % |
| `aviatrix.gateway.disk.avail` | gauge | Byte | Available disk space |
| `aviatrix.gateway.disk.total` | gauge | Byte | Total disk space |
| `aviatrix.gateway.disk.used` | gauge | Byte | Used disk space |
| `aviatrix.gateway.disk.used.percent` | gauge | Percent | Disk utilization % |

### Per-Core CPU Metrics

Same metric keys as aggregate, with an added `core` dimension:

| Metric | Dimension | Description |
|--------|-----------|-------------|
| `aviatrix.gateway.cpu.idle` | `core="0"`, `core="1"`, ... | Per-core idle (100 - busy_avg) |
| `aviatrix.gateway.cpu.usage` | `core="0"`, `core="aggregate"` | Per-core usage (busy_avg) |

### Network Statistics (`AviatrixGwNetStats`)

Dimensions: `gateway`, `alias`, `source`, `interface`, `public_ip` (if present), `private_ip`

| Metric | Type | Unit | Description |
|--------|------|------|-------------|
| `aviatrix.gateway.net.bytes_rx` | gauge | BytePerSecond | Receive rate |
| `aviatrix.gateway.net.bytes_tx` | gauge | BytePerSecond | Transmit rate |
| `aviatrix.gateway.net.bytes_total_rate` | gauge | BytePerSecond | Total throughput |
| `aviatrix.gateway.net.rx_cumulative` | gauge | Byte | Cumulative bytes received |
| `aviatrix.gateway.net.tx_cumulative` | gauge | Byte | Cumulative bytes transmitted |
| `aviatrix.gateway.net.rx_tx_cumulative` | gauge | Byte | Cumulative total bytes |
| `aviatrix.gateway.net.conntrack.count` | gauge | Count | Current conntrack entries |
| `aviatrix.gateway.net.conntrack.avail` | gauge | Count | Available conntrack slots |
| `aviatrix.gateway.net.conntrack.usage` | gauge | Percent | Conntrack usage % (rate x 100) |
| `aviatrix.gateway.net.conntrack_limit_exceeded` | count | Count | Conntrack limit exceeded (delta) |
| `aviatrix.gateway.net.bw_in_limit_exceeded` | count | Count | Inbound BW limit exceeded (delta) |
| `aviatrix.gateway.net.bw_out_limit_exceeded` | count | Count | Outbound BW limit exceeded (delta) |
| `aviatrix.gateway.net.pps_limit_exceeded` | count | Count | PPS limit exceeded (delta) |
| `aviatrix.gateway.net.linklocal_limit_exceeded` | count | Count | Link-local limit exceeded (delta) |

## Rate/Cumulative Unit Conversion

Raw syslog values use human-readable units ("54.07Kb", "2.49GB"). The MINT builder converts all values to bytes using filter 94's preserved raw strings:

| Raw Value | Converted | Unit |
|-----------|-----------|------|
| `54.07Kb` | 55,367.68 | BytePerSecond |
| `126.78Kb` | 129,822.72 | BytePerSecond |
| `2.49GB` | 2,673,066,803.2 | Byte |
| `510.30MB` | 535,097,549.8 | Byte |

Filter 94 (`94-save-raw-net-rates.conf`) saves the original string values to `[@metadata]` before filter 95 converts them to truncated integers.

## Building the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh dynatrace-metrics
```

## Local Testing

1. **Start webhook viewer**:
   ```bash
   cd test-tools/webhook-viewer/local && ./run.sh
   ```

2. **Create a webhook session** in the UI at http://localhost:8080

3. **Assemble and run Logstash**:
   ```bash
   cd logstash-configs
   ./scripts/assemble-config.sh dynatrace-metrics

   docker run --rm \
     -v $(pwd)/assembled:/config \
     -v $(pwd)/patterns:/usr/share/logstash/patterns \
     -e DT_METRICS_URL=http://host.docker.internal:8080/<session-id> \
     -e DT_API_TOKEN=test \
     -e DT_METRIC_SOURCE=aviatrix \
     -e LOG_PROFILE=all \
     -e XPACK_MONITORING_ENABLED=false \
     -p 5002:5000 \
     docker.elastic.co/logstash/logstash:8.16.2 \
     logstash -f /config/dynatrace-metrics-full.conf
   ```

4. **Stream test logs**:
   ```bash
   cd test-tools/sample-logs
   ./generate-current-samples.sh --overwrite
   ./stream-logs.py --port 5002 --filter netstats -v
   ./stream-logs.py --port 5002 --filter sysstats -v
   ```

5. **Validate output**:
   ```bash
   # Copy payloads from webhook viewer, then:
   ./test-tools/validate-dynatrace-metrics.py --no-timestamp-check -v captured-output.txt
   ./test-tools/validate-dynatrace-metrics.py --check-completeness captured-output.txt
   ```

### Spot-Check Values

| Input | Expected Output |
|-------|-----------------|
| `total_rx_rate=54.07Kb` | `aviatrix.gateway.net.bytes_rx gauge,55367.68` |
| `memory_available=6762800` (kB) | `aviatrix.gateway.memory.avail gauge,6925107200` |
| `conntrack_usage_rate=0.05` | `aviatrix.gateway.net.conntrack.usage gauge,5.0` |

## Dynatrace Query Examples

```
# Gateway CPU utilization over time
timeseries avg(aviatrix.gateway.cpu.usage), by:{gateway}

# Per-core CPU hotspots
timeseries max(aviatrix.gateway.cpu.usage), by:{gateway, core}
| filter core != "aggregate"

# Network throughput
timeseries avg(aviatrix.gateway.net.bytes_rx), by:{gateway, interface}

# Conntrack usage approaching limit
timeseries max(aviatrix.gateway.net.conntrack.usage), by:{gateway}
| filter value > 80
```

## Troubleshooting

### No metrics in Dynatrace

1. Verify platform token has `storage:metrics:write` scope and IAM policy is bound
2. Check Logstash logs: `docker logs <container>`
3. Test API directly:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" -X POST "${DT_METRICS_URL}" \
     -H "Authorization: Bearer ${DT_API_TOKEN}" \
     -H "Content-Type: text/plain" \
     -d "test.metric,gateway=\"test\" gauge,42 $(date +%s)000"
   # Expect: 202
   ```
4. For 401/403/404 errors, see the [troubleshooting matrix](../../../docs/DYNATRACE_SETUP.md#7-troubleshooting) in the setup guide

### Rate values are wrong (truncated integers)

Verify filter 94 is present in `filters/94-save-raw-net-rates.conf`. This filter saves raw strings like "54.07Kb" to `[@metadata]` before filter 95 converts them to truncated integers. Without filter 94, rate values lose precision (e.g. "54.07Kb" becomes 54 instead of 55,367.68).

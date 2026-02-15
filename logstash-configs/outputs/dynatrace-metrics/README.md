# Dynatrace Metrics Output

Sends Aviatrix gateway metrics to Dynatrace Metrics Ingest API v2 using the MINT protocol.

## Prerequisites

1. **Dynatrace Environment**
   - Environment ID (found in your Dynatrace URL: `https://{environmentId}.live.dynatrace.com`)
   - Region: `live` (default), `apps`, or custom domain

2. **API Token** with `metrics.ingest` scope
   - Create at: Settings → Integration → Dynatrace API → Generate token
   - Required scope: **metrics.ingest**

## Environment Variables

```bash
# Required
export DT_ENVIRONMENT_ID="abc12345"        # Your Dynatrace environment ID
export DT_API_TOKEN="dt0c01.ABC123..."     # API token with metrics.ingest scope

# Optional
export DT_REGION="live"                     # Region: live (default), apps, or custom
export LOG_PROFILE="networking"              # Filter: all (default) or networking
```

## Metrics Generated

### Network Statistics (`AviatrixGwNetStats`)

| Metric | Type | Description |
|--------|------|-------------|
| `aviatrix.gateway.net.rx.rate.bytes` | gauge | Receive rate in bytes/sec |
| `aviatrix.gateway.net.tx.rate.bytes` | gauge | Transmit rate in bytes/sec |
| `aviatrix.gateway.net.total.rate.bytes` | gauge | Total throughput in bytes/sec |
| `aviatrix.gateway.net.conntrack.count` | gauge | Current connection tracking count |
| `aviatrix.gateway.net.conntrack.allowance.available` | gauge | Available connection slots |
| `aviatrix.gateway.net.conntrack.usage.rate` | gauge | Connection tracking usage (0-1) |
| `aviatrix.gateway.net.conntrack.limit.exceeded` | gauge | Times limit was hit |
| `aviatrix.gateway.net.bw.in.limit.exceeded` | count | Inbound bandwidth limit hits |
| `aviatrix.gateway.net.bw.out.limit.exceeded` | count | Outbound bandwidth limit hits |
| `aviatrix.gateway.net.pps.limit.exceeded` | count | Packets-per-second limit hits |

### System Statistics (`AviatrixGwSysStats`)

| Metric | Type | Description |
|--------|------|-------------|
| `aviatrix.gateway.cpu.busy.pct` | gauge | Overall CPU busy % (100 - idle) |
| `aviatrix.gateway.memory.used.pct` | gauge | Memory utilization % |
| `aviatrix.gateway.memory.available.kb` | gauge | Available memory in KB |
| `aviatrix.gateway.memory.free.kb` | gauge | Free memory in KB |
| `aviatrix.gateway.disk.used.pct` | gauge | Disk utilization % |
| `aviatrix.gateway.disk.free.kb` | gauge | Free disk space in KB |

### Per-Core CPU Metrics (≤16 cores)

| Metric | Type | Description | Dimension |
|--------|------|-------------|-----------|
| `aviatrix.gateway.cpu.core.busy.max` | gauge | Peak CPU busy % | `core.id` (0-15, aggregate) |
| `aviatrix.gateway.cpu.core.busy.avg` | gauge | Average CPU busy % | `core.id` (0-15, aggregate) |
| `aviatrix.gateway.cpu.core.busy.min` | gauge | Minimum CPU busy % | `core.id` (0-15, aggregate) |

### High Core Count Metrics (>16 cores)

| Metric | Type | Description |
|--------|------|-------------|
| `aviatrix.gateway.cpu.individual.max.peak` | gauge | Highest busy % across all cores |
| `aviatrix.gateway.cpu.individual.avg.mean` | gauge | Mean of all core averages |
| `aviatrix.gateway.cpu.cores.over.80.pct` | gauge | Count of cores >80% busy |
| `aviatrix.gateway.cpu.cores.over.90.pct` | gauge | Count of cores >90% busy |
| `aviatrix.gateway.cpu.core.count` | gauge | Total number of CPU cores |

## Dimension

All metrics include the dimension:
- `gateway.name` - Gateway name/alias for filtering and grouping

## Docker Run Example

```bash
docker run -d \
  --name aviatrix-logstash-dynatrace \
  -p 5000:5000/udp \
  -p 5000:5000/tcp \
  -e DT_ENVIRONMENT_ID="abc12345" \
  -e DT_API_TOKEN="dt0c01.ABC123..." \
  -e DT_REGION="live" \
  -e LOG_PROFILE="networking" \
  -v $(pwd)/logstash-configs/assembled/dynatrace-metrics-full.conf:/usr/share/logstash/pipeline/logstash.conf:ro \
  -v $(pwd)/logstash-configs/patterns:/usr/share/logstash/patterns:ro \
  docker.elastic.co/logstash/logstash:8.11.0
```

## Building the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh dynatrace-metrics
```

This creates `assembled/dynatrace-metrics-full.conf` ready for deployment.

## Dynatrace Dashboards

### Example Query: Gateway CPU Utilization

```
timeseries max(aviatrix.gateway.cpu.busy.pct), by:{gateway.name}
```

### Example Query: Per-Core CPU Hotspots

```
timeseries max(aviatrix.gateway.cpu.core.busy.max), by:{gateway.name, core.id}
| filter core.id != "aggregate"
```

### Example Query: High Core Count Gateway Summary

```
timeseries
  max(aviatrix.gateway.cpu.individual.max.peak),
  avg(aviatrix.gateway.cpu.cores.over.80.pct),
  by:{gateway.name}
| filter in(gateway.name, "massive-gateway")
```

## Alerting Examples

### Alert: Any Core Over 90% Busy

**Condition:**
```
aviatrix.gateway.cpu.core.busy.max > 90
and core.id != "aggregate"
```

**Alert Name:** "Gateway CPU core hotspot"

### Alert: High Core Count Gateway Stress

**Condition:**
```
aviatrix.gateway.cpu.cores.over.80.pct > 8
or aviatrix.gateway.cpu.individual.max.peak > 95
```

**Alert Name:** "High-core gateway CPU stress"

### Alert: Network Conntrack Exhaustion

**Condition:**
```
aviatrix.gateway.net.conntrack.usage.rate > 0.9
or aviatrix.gateway.net.conntrack.limit.exceeded > 100
```

**Alert Name:** "Gateway connection tracking near capacity"

## Metric Cardinality

- **Low core count gateway** (2-8 cores): ~40-50 metrics per 30-second interval
- **Medium gateway** (8-16 cores): ~60-80 metrics per interval
- **High core count gateway** (32-96 cores): ~30 metrics per interval (summary stats only)

All metrics are sent with minimal overhead using the MINT text protocol.

## Troubleshooting

### No metrics appearing in Dynatrace

1. Verify API token has `metrics.ingest` scope
2. Check Logstash logs for HTTP errors: `docker logs aviatrix-logstash-dynatrace`
3. Test API connection:
   ```bash
   curl -X POST \
     "https://${DT_ENVIRONMENT_ID}.live.dynatrace.com/api/v2/metrics/ingest" \
     -H "Authorization: Api-Token ${DT_API_TOKEN}" \
     -H "Content-Type: text/plain" \
     -d "test.metric,gateway.name=\"test\" gauge,42 $(date +%s)000"
   ```

### Metrics delayed or missing

- Dynatrace ingests metrics asynchronously, allow 1-2 minutes for data to appear
- Check metric names in: Settings → Metrics → Custom metrics

### Rate limiting

Dynatrace has rate limits on metrics ingest. If you have 100+ gateways:
- Use `LOG_PROFILE=networking` to reduce volume
- Consider batching or sampling strategies

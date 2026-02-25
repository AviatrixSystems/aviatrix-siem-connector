# Zabbix Metrics Output

Sends Aviatrix gateway **networking metrics** (gw_sys_stats + gw_net_stats) to Zabbix using the **Dependent Items pattern**: Logstash sends one JSON blob per event type to a master trapper item, and Zabbix 7.x JSONPath preprocessing fans out into individual metrics.

## Prerequisites

- **Zabbix Server 7.0+** with trapper port 10051 accessible from the Logstash host
- **Logstash 8.x** with `logstash-output-zabbix` plugin installed
- Network connectivity from Logstash to Zabbix server on port 10051 (TCP)

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ZABBIX_SERVER` | Yes | — | Zabbix server/proxy hostname or IP |
| `ZABBIX_PORT` | No | `10051` | Zabbix trapper port |
| `ZABBIX_HOST_PREFIX` | No | `""` | Prefix for Zabbix host names (e.g. `avx-`) |
| `LOG_PROFILE` | No | `all` | Log type filter (`networking` recommended) |

## Quick Start

### 1. Import the Template

Import the Zabbix template from `template/aviatrix_gateway_template.yaml`:

1. In Zabbix UI: **Data collection** > **Templates** > **Import**
2. Select `aviatrix_gateway_template.yaml`
3. Click **Import**

The template "Aviatrix Gateway Metrics" provides:
- 2 master trapper items (sys_stats raw JSON, net_stats raw JSON)
- 11 dependent items for system metrics (CPU, memory, disk)
- 17 per-vCPU items (cores 0-7, idle + usage each, plus core count)
- 14 dependent items for network metrics (throughput, conntrack, limit counters)
- 4 triggers (CPU > 90%, memory > 85%, disk > 90%, conntrack > 80%)

### 2. Create Hosts

Create a Zabbix host for each gateway. The host name must match the value sent by Logstash:

- **Host name**: `<ZABBIX_HOST_PREFIX><gateway_name>` (e.g., `avx-gw-useast1-prod`)
- **Template**: Link "Aviatrix Gateway Metrics"
- **No agent interface needed** — data arrives via trapper

If `ZABBIX_HOST_PREFIX` is empty (default), the host name equals the Aviatrix gateway name.

### 3. Build the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh zabbix
```

This creates `assembled/zabbix-full.conf`.

### 4. Deploy Logstash

#### Option A: Podman/Docker (local testing)

```bash
# Build container with plugin baked in
cd logstash-configs
podman build -t logstash-avx-zabbix -f outputs/zabbix/Containerfile .

# Run
podman run -d --name logstash-zabbix-test \
  -e ZABBIX_SERVER=10.0.0.50 \
  -e ZABBIX_PORT=10051 \
  -e ZABBIX_HOST_PREFIX="" \
  -e LOG_PROFILE=networking \
  -e XPACK_MONITORING_ENABLED=false \
  -p 5002:5000 -p 5002:5000/udp \
  logstash-avx-zabbix
```

#### Option B: VM/EC2 deployment

Use the Terraform deployment in `deployments/` with output_type `zabbix`.

## Metrics Reference

### System Stats (aviatrix.sys_stats.raw)

| Zabbix Item Key | Description | Type | Units |
|----------------|-------------|------|-------|
| `aviatrix.cpu.idle` | CPU idle % | Float | % |
| `aviatrix.cpu.usage` | CPU usage % (100 - idle) | Float | % |
| `aviatrix.memory.available` | Available memory | Unsigned | B |
| `aviatrix.memory.total` | Total memory | Unsigned | B |
| `aviatrix.memory.free` | Free memory | Unsigned | B |
| `aviatrix.memory.used` | Used memory | Unsigned | B |
| `aviatrix.memory.usage` | Memory usage % | Float | % |
| `aviatrix.disk.available` | Available disk | Unsigned | B |
| `aviatrix.disk.total` | Total disk | Unsigned | B |
| `aviatrix.disk.used` | Used disk | Unsigned | B |
| `aviatrix.disk.usage` | Disk usage % | Float | % |
| `aviatrix.cpu.core_count` | Number of vCPUs | Unsigned | — |
| `aviatrix.cpu.idle[0..7]` | Per-core idle % | Float | % |
| `aviatrix.cpu.usage[0..7]` | Per-core usage % | Float | % |

### Network Stats (aviatrix.net_stats.raw[eth0])

| Zabbix Item Key | Description | Type | Units |
|----------------|-------------|------|-------|
| `aviatrix.net.bytes_rx[eth0]` | RX rate | Float | Bps |
| `aviatrix.net.bytes_tx[eth0]` | TX rate | Float | Bps |
| `aviatrix.net.bytes_total_rate[eth0]` | Total rate | Float | Bps |
| `aviatrix.net.rx_cumulative[eth0]` | Cumulative RX | Unsigned | B |
| `aviatrix.net.tx_cumulative[eth0]` | Cumulative TX | Unsigned | B |
| `aviatrix.net.rxtx_cumulative[eth0]` | Cumulative total | Unsigned | B |
| `aviatrix.net.conntrack.count[eth0]` | Current conntrack entries | Unsigned | — |
| `aviatrix.net.conntrack.available[eth0]` | Available conntrack entries | Unsigned | — |
| `aviatrix.net.conntrack.usage[eth0]` | Conntrack usage % | Float | % |
| `aviatrix.net.conntrack_limit_exceeded[eth0]` | Conntrack limit exceeded | Unsigned | — |
| `aviatrix.net.bw_in_limit_exceeded[eth0]` | BW in limit exceeded | Unsigned | — |
| `aviatrix.net.bw_out_limit_exceeded[eth0]` | BW out limit exceeded | Unsigned | — |
| `aviatrix.net.pps_limit_exceeded[eth0]` | PPS limit exceeded | Unsigned | — |
| `aviatrix.net.linklocal_limit_exceeded[eth0]` | Link-local limit exceeded | Unsigned | — |

## Local Testing

1. Stream test logs:
   ```bash
   cd test-tools/sample-logs
   ./generate-current-samples.sh --overwrite
   ./stream-logs.py --port 5002 --filter sysstats -v
   ./stream-logs.py --port 5002 --filter netstats -v
   ```

2. Verify in Zabbix UI: **Monitoring** > **Latest data** > filter by host

## Troubleshooting

- **"host not found"**: Ensure the Zabbix host name matches `ZABBIX_HOST_PREFIX` + gateway name exactly
- **No data arriving**: Check trapper port 10051 is reachable (`nc -zv <zabbix-ip> 10051`)
- **Per-core items empty**: Normal if gateway has fewer than 8 cores — items for missing cores receive no updates
- **Plugin not found**: Run `logstash-plugin install logstash-output-zabbix` or use the Containerfile

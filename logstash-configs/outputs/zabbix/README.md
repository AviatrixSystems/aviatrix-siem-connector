# Zabbix Metrics Output

Sends Aviatrix gateway **networking metrics** (gw_sys_stats + gw_net_stats) to Zabbix using the **Dependent Items pattern**: Logstash sends one JSON blob per event type to a master trapper item, and Zabbix 7.x JSONPath preprocessing fans out into individual metrics.

## Prerequisites

- **Zabbix Server 7.0+** with trapper port 10051 accessible from the Logstash host
- **Logstash 8.x** with `logstash-output-zabbix` plugin installed
- Network connectivity from Logstash to Zabbix server on port 10051 (TCP)

> **Important**: Zabbix will silently reject data for hosts that don't exist. You must complete steps 1-2 below (import the template, create a host group, and create a host for each gateway) **before** data will appear in Zabbix. There is no auto-discovery — if a new gateway starts sending logs and no matching host exists, those events are dropped.

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

### 2. Create a Host Group

Create a host group to organize your Aviatrix gateway hosts (the template import does **not** create one):

1. In Zabbix UI: **Data collection** > **Host groups** > **Create host group**
2. Name: `Aviatrix Gateways` (or any name you prefer)

### 3. Create Hosts

Create a Zabbix host for **each** Aviatrix gateway that will send logs. Zabbix rejects trapper data for unknown hosts, so this step is required before any metrics will appear.

- **Host name**: `<ZABBIX_HOST_PREFIX><gateway_name>` (e.g., `avx-gw-useast1-prod`)
- **Host group**: Add to the host group created above
- **Template**: Link "Aviatrix Gateway Metrics"
- **No agent interface needed** — data arrives via trapper items

If `ZABBIX_HOST_PREFIX` is empty (default), the host name must exactly match the Aviatrix gateway name as it appears in CoPilot.

#### Finding your gateway names

Gateway names are visible in Aviatrix CoPilot under **Cloud Fabric** > **Gateways**. You can also check the Logstash logs after initial deployment — rejected events appear as:

```
"processing error" => "host [gateway-name] not found"
```

#### Creating hosts via Zabbix API

For environments with many gateways, use the API instead of the UI. First, get the template and host group IDs:

```bash
ZABBIX_URL="http://<zabbix-server>/api_jsonrpc.php"
ZABBIX_TOKEN="<your-api-token>"

# Get template ID for "Aviatrix Gateway Metrics"
curl -s -X POST "$ZABBIX_URL" \
  -H "Authorization: Bearer $ZABBIX_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"template.get","params":{"filter":{"host":"Aviatrix Gateway Metrics"}},"id":1}' \
  | jq '.result[0].templateid'

# Get host group ID for "Aviatrix Gateways"
curl -s -X POST "$ZABBIX_URL" \
  -H "Authorization: Bearer $ZABBIX_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"hostgroup.get","params":{"filter":{"name":"Aviatrix Gateways"}},"id":1}' \
  | jq '.result[0].groupid'
```

Then create a host (repeat for each gateway):

```bash
curl -s -X POST "$ZABBIX_URL" \
  -H "Authorization: Bearer $ZABBIX_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.create",
    "params": {
      "host": "<gateway-name>",
      "groups": [{"groupid": "<GROUP_ID>"}],
      "templates": [{"templateid": "<TEMPLATE_ID>"}]
    },
    "id": 1
  }'
```

> **Note**: Zabbix 7.x API uses `Authorization: Bearer <token>` header authentication, not the legacy `"auth"` JSON parameter.

### 4. Build the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh zabbix
```

This creates `assembled/zabbix-full.conf`.

### 5. Deploy Logstash

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

#### Option B: AWS EC2 deployment

Use the Terraform deployment in `deployments/aws-ec2-single-instance/` or `deployments/aws-ec2-autoscale/` with `output_type = "zabbix"`.

#### Option C: AWS ECS Fargate deployment

Use the Terraform deployment in `deployments/aws-ecs-fargate/` with `output_type = "zabbix"`. Config is baked into the container image.

> **Recommended**: Set `LOG_PROFILE=networking` for all Zabbix deployments. The Zabbix output only processes `gw_sys_stats` and `gw_net_stats` events — other log types (security, tunnel status, etc.) are not forwarded, so there's no benefit to receiving them.

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

## Important Notes

### Multi-interface gateways

The template only defines network trapper items for `eth0`. Gateways with multiple interfaces (e.g., `eth-fn0`, `eth-fn1`) will report network stats for all interfaces, but only `eth0` data is accepted. Events for other interfaces are rejected by Zabbix with `"processing error" => "item [...] not found"`. This is expected behavior — the rejected events appear in Logstash logs but cause no data loss for the `eth0` interface.

### Adding new gateways

When a new gateway is added in Aviatrix CoPilot, you must create a corresponding host in Zabbix (step 3 above) before its metrics will be stored. Monitor Logstash logs for `"host not found"` errors to detect gateways that need to be added.

## Troubleshooting

- **"host [name] not found"**: The gateway is sending data but no matching host exists in Zabbix. Create a host with that exact name and link the template (see step 3)
- **"item [...] not found"**: Usually caused by non-eth0 interface events (see Multi-interface gateways above). No action needed
- **No data arriving**: Check trapper port 10051 is reachable from Logstash (`nc -zv <zabbix-ip> 10051`)
- **Per-core items empty**: Normal if gateway has fewer than 8 cores — items for missing cores receive no updates
- **Plugin not found**: Run `logstash-plugin install logstash-output-zabbix` or use the Containerfile
- **44 items but only 30 with data**: The 14 items without data are per-core metrics for vCPU cores that don't exist on the gateway (template provisions cores 0-7)

# Dynatrace Logs Output

Sends Aviatrix event logs to Dynatrace Logs Ingest API v2 as structured JSON with `aviatrix.*` attributes for filtering and correlation in Grail/DQL.

## Prerequisites

1. **Dynatrace Environment** with a logs ingest endpoint URL
2. **API Token** with `logs.ingest` scope
   - Create at: Access Tokens > Generate new token > Enable "Ingest logs"

## Environment Variables

```bash
# Required
export DT_LOGS_URL="https://abc12345.live.dynatrace.com/api/v2/logs/ingest"
export DT_LOGS_TOKEN="dt0c01.ABC123..."     # API token with logs.ingest scope

# Optional
export DT_LOG_SOURCE="aviatrix"              # log.source attribute (default: aviatrix)
export LOG_PROFILE="all"                     # Filter: all (default), security, or networking
```

## Log Types

### Security Events (LOG_PROFILE: `security` or `all`)

| Tag | aviatrix.event.type | Severity | Content Example |
|-----|---------------------|----------|-----------------|
| `suricata` | `IDSAlert` | 1=ERROR, 2=WARN, 3+=INFORMATIONAL | `IDS Alert: ET MALWARE ... 10.0.0.1:443 -> 10.0.0.2:54321` |
| `mitm` | `WebInspection` | DENY=WARN, ALLOW=INFORMATIONAL | `L7 DCF Allow: 10.0.0.1 -> example.com` |
| `microseg` | `DCFPolicyEvent` | DENY=WARN, ALLOW=INFORMATIONAL | `L4 DCF Deny: 10.0.0.1:8080 -> 10.0.0.2:443 TCP` |
| `fqdn` | `FQDNFilter` | blocked=WARN, else=INFORMATIONAL | `FQDN Allow: 10.0.0.1 -> api.example.com (1.2.3.4) on gw1` |
| `cmd` | `ControllerAudit` | result!=Success=WARN, else=INFORMATIONAL | `Controller API: setup_gateway by admin - Success` |

### Networking Events (LOG_PROFILE: `networking` or `all`)

| Tag | aviatrix.event.type | Severity | Content Example |
|-----|---------------------|----------|-----------------|
| `tunnel_status` | `TunnelStatus` | Down=WARN, Up=INFORMATIONAL | `Tunnel Down: k8s-transit(AWS us-east-2) -> west-transit(AWS us-west-2)` |

## Attribute Reference

### Standard Attributes (all events)

| Attribute | Description |
|-----------|-------------|
| `timestamp` | RFC3339 from Logstash @timestamp |
| `severity` | Dynatrace severity level |
| `content` | Human-readable event summary |
| `log.source` | Configurable source tag (default: "aviatrix") |
| `aviatrix.event.type` | Event category for DQL filtering |

### TunnelStatus Attributes

| Attribute | Source | Example |
|-----------|--------|---------|
| `aviatrix.tunnel.src_gw` | Parsed from `src_gw` | `k8s-transit` |
| `aviatrix.tunnel.src_cloud` | Parsed from `src_gw` | `aws` |
| `aviatrix.tunnel.src_region` | Parsed from `src_gw` | `us-east-2` |
| `aviatrix.tunnel.dst_gw` | Parsed from `dst_gw` | `west-transit` |
| `aviatrix.tunnel.dst_cloud` | Parsed from `dst_gw` | `aws` |
| `aviatrix.tunnel.dst_region` | Parsed from `dst_gw` | `us-west-2` |
| `aviatrix.tunnel.new_state` | Direct | `Down` |
| `aviatrix.tunnel.old_state` | Direct | `Up` |
| `cloud.provider` | Dynatrace semantic attr (from src) | `aws` |
| `cloud.region` | Dynatrace semantic attr (from src) | `us-east-2` |

### DCF Policy Attributes (microseg + mitm)

| Attribute | Description |
|-----------|-------------|
| `aviatrix.dcf.layer` | `L4` (microseg) or `L7` (mitm) |
| `aviatrix.dcf.action` | `ALLOW` or `DENY` |
| `aviatrix.dcf.enforced` | Policy enforcement state |
| `aviatrix.dcf.policy_uuid` | Policy UUID |
| `aviatrix.dcf.src_ip` / `dst_ip` | Source/destination IP |
| `aviatrix.dcf.src_port` / `dst_port` | Source/destination port |
| `aviatrix.dcf.protocol` | Network protocol |
| `aviatrix.dcf.gateway` | Reporting gateway hostname |
| `aviatrix.dcf.sni_hostname` | TLS SNI hostname (L7 only) |
| `aviatrix.dcf.url` | URL parts (L7 only) |
| `aviatrix.dcf.session_*` | Session fields (8.2+ L4 only) |

### IDS Alert Attributes (suricata)

| Attribute | Description |
|-----------|-------------|
| `aviatrix.ids.signature` | Alert signature string |
| `aviatrix.ids.severity` | Suricata severity (1=high, 2=med, 3=low) |
| `aviatrix.ids.category` | Alert category |
| `aviatrix.ids.signature_id` | Signature ID number |
| `aviatrix.ids.src_ip` / `dst_ip` | Source/destination IP |
| `aviatrix.ids.src_port` / `dst_port` | Source/destination port |
| `aviatrix.ids.protocol` | Network protocol |
| `aviatrix.ids.gateway` | Reporting gateway hostname |
| `aviatrix.ids.flow.*` | Flow counters (pkts/bytes to server/client) |
| `aviatrix.ids.http.*` | HTTP metadata (hostname, url, method, status) |
| `aviatrix.ids.tls.*` | TLS metadata (sni, subject, ja3_hash) |

### FQDN Filter Attributes

| Attribute | Description |
|-----------|-------------|
| `aviatrix.firewall.gateway` | Gateway name |
| `aviatrix.firewall.src_ip` | Source IP |
| `aviatrix.firewall.dst_ip` | Destination IP |
| `aviatrix.firewall.hostname` | FQDN hostname |
| `aviatrix.firewall.state` | Filter state (allowed/blocked) |
| `aviatrix.firewall.rule` | Matching rule |

### Controller Audit Attributes

| Attribute | Description |
|-----------|-------------|
| `aviatrix.controller.action` | API action performed |
| `aviatrix.controller.result` | Success/Failure |
| `aviatrix.controller.username` | User who performed action |
| `aviatrix.controller.reason` | Failure reason (if any) |

## Building the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh dynatrace-logs
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
   ./scripts/assemble-config.sh dynatrace-logs

   docker run --rm \
     -v $(pwd)/assembled:/config \
     -v $(pwd)/patterns:/usr/share/logstash/patterns \
     -e DT_LOGS_URL=http://host.docker.internal:8080/<session-id> \
     -e DT_LOGS_TOKEN=test \
     -e DT_LOG_SOURCE=aviatrix \
     -e LOG_PROFILE=all \
     -e XPACK_MONITORING_ENABLED=false \
     -p 5002:5000 \
     docker.elastic.co/logstash/logstash:8.16.2 \
     logstash -f /config/dynatrace-logs-full.conf
   ```

4. **Stream test logs**:
   ```bash
   cd test-tools/sample-logs
   ./generate-current-samples.sh --overwrite
   ./stream-logs.py --port 5002 -v
   ```

5. **Inspect output** in the webhook viewer. Each POST body should be a JSON array containing one log event object with `timestamp`, `severity`, `content`, and `aviatrix.*` attributes.

## DQL Query Examples

```
# All tunnel down events (last 24h)
fetch logs
| filter log.source == "aviatrix"
| filter aviatrix.event.type == "TunnelStatus"
| filter aviatrix.tunnel.new_state == "Down"
| sort timestamp desc

# Tunnel flapping (>4 state changes in 15 min)
fetch logs
| filter aviatrix.event.type == "TunnelStatus"
| summarize changes = count(), by:{aviatrix.tunnel.src_gw, aviatrix.tunnel.dst_gw, bin(timestamp, 15m)}
| filter changes > 4

# All DCF deny events
fetch logs
| filter aviatrix.event.type == "DCFPolicyEvent" or aviatrix.event.type == "WebInspection"
| filter aviatrix.dcf.action == "DENY"
| sort timestamp desc

# IDS alerts by severity
fetch logs
| filter aviatrix.event.type == "IDSAlert"
| summarize count(), by:{aviatrix.ids.severity, aviatrix.ids.category}
| sort count desc

# Controller audit trail for a user
fetch logs
| filter aviatrix.event.type == "ControllerAudit"
| filter aviatrix.controller.username == "admin"
| sort timestamp desc

# Event count by type and severity
fetch logs
| filter log.source == "aviatrix"
| summarize count(), by:{aviatrix.event.type, loglevel}
| sort count desc
```

## Troubleshooting

### No logs in Dynatrace

1. Verify API token has `logs.ingest` scope
2. Check Logstash logs: `docker logs <container>`
3. Test API:
   ```bash
   curl -X POST "${DT_LOGS_URL}" \
     -H "Authorization: Api-Token ${DT_LOGS_TOKEN}" \
     -H "Content-Type: application/json; charset=utf-8" \
     -d '[{"content":"test log","severity":"INFORMATIONAL","log.source":"aviatrix"}]'
   # Expect: 204 No Content
   ```

### Events missing attributes

Verify the correct filter files are present in the pipeline. The Dynatrace log builders depend on fields extracted by filters 10-16 (grok parsing) and 90 (timestamp normalization).

### Combined with Metrics

To send both metrics AND logs from the same Logstash instance, use the `dynatrace` combined output type instead:
```bash
./scripts/assemble-config.sh dynatrace
```

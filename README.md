# Aviatrix SIEM Connector

Flexible and scalable log integration between Aviatrix and 3rd party SIEM, logging, and observability tools.

The connector is built on top of Logstash with an Aviatrix-validated log parsing configuration. The engine is best-effort community supported.

## Architecture

```
                         Aviatrix Cloud Network
            ┌──────────────────────────────────────────┐
            │                                          │
            │  Gateways              Controller        │
            │  ├─ Distributed        ├─ API Audit      │
            │  │  Cloud Firewall     │  Logs           │
            │  ├─ Suricata IDS       └─ Tunnel Status  │
            │  ├─ Network Stats                        │
            │  └─ System Stats                         │
            │                                          │
            └──────────────┬───────────────────────────┘
                           │ Syslog (UDP/TCP 5000)
                           ▼
     ┌─────────────────────────────────────────────────────┐
     │              SIEM Connector                          │
     │                                                     │
     │  ┌───────────┐  ┌───────────┐  ┌────────────────┐  │
     │  │ 1. Parse  │  │ 2. Norm-  │  │ 3. Route by    │  │
     │  │  & Tag    ├─►│  alize &  ├─►│  Log Profile   │  │
     │  │           │  │  Convert  │  │  & Destination  │  │
     │  └───────────┘  └───────────┘  └────────────────┘  │
     │                                                     │
     │  8 log types • Grok + JSON parsing • ASIM support   │
     └──────────┬──────────┬───────────┬──────────┬────────┘
                │          │           │          │
                ▼          ▼           ▼          ▼
           ┌────────┐ ┌────────┐ ┌──────────┐ ┌───────┐
           │ Splunk │ │ Azure  │ │Dynatrace │ │Zabbix │
           │  HEC   │ │Sentinel│ │          │ │       │
           └────────┘ └────────┘ └──────────┘ └───────┘
```

### Log Types

| Category | Log Type | Description |
|----------|----------|-------------|
| **Security** | FQDN Firewall | DNS-based firewall rule hits |
| | L4 Microsegmentation | eBPF-enforced network policy (allow/deny) |
| | L7/TLS Inspection | Deep packet inspection via TLS proxy |
| | Suricata IDS | Intrusion detection alerts |
| **Networking** | Gateway Network Stats | Interface throughput, packet rates |
| | Tunnel Status | Tunnel up/down state changes |
| **Operations** | Controller API | API calls and admin actions |
| | Gateway System Stats | CPU, memory, disk utilization |

### Pipeline Stages

1. **Parse & Tag** — Grok patterns and JSON codec extract structured fields from raw syslog. Each event is tagged by log type for downstream routing.
2. **Normalize & Convert** — Timestamps are standardized, numeric fields are type-cast, and (for Azure) ASIM schema fields are mapped. Microseg events are throttled to reduce volume.
3. **Route** — Events are directed to the configured output based on the `LOG_PROFILE` setting (`all`, `security`, or `networking`), which controls which log categories are forwarded.

## Quick Start

### 1. Build the Logstash Configuration

```bash
cd logstash-configs

# For Splunk output
./scripts/assemble-config.sh splunk-hec

# For Azure Log Analytics output
./scripts/assemble-config.sh azure-log-ingestion

# For Dynatrace output (metrics + logs combined)
./scripts/assemble-config.sh dynatrace

# For Zabbix output
./scripts/assemble-config.sh zabbix
```

This generates a complete configuration file in `logstash-configs/assembled/`.

### 2. Deploy

Choose a deployment architecture from `deployments/` and follow its README:

| Architecture | Description |
|--------------|-------------|
| [aws-ec2-autoscale](./deployments/aws-ec2-autoscale) | HA autoscaling EC2 instances behind NLB |
| [aws-ec2-single-instance](./deployments/aws-ec2-single-instance) | Single EC2 instance |
| [azure-aci](./deployments/azure-aci) | Azure Container Instance |

### 3. Configure Aviatrix

Point your Aviatrix Controller/CoPilot syslog export to the deployed engine's IP on port 5000 (UDP/TCP).

## Configuration Structure

```
logstash-configs/
├── inputs/                 # Syslog listener (UDP/TCP 5000)
├── filters/                # Log parsing modules
├── outputs/                # Destination-specific outputs
│   ├── splunk-hec/         # Splunk HTTP Event Collector
│   ├── azure-log-ingestion/# Azure Log Analytics
│   ├── dynatrace/          # Dynatrace (metrics + logs)
│   ├── dynatrace-metrics/  # Dynatrace metrics only
│   ├── dynatrace-logs/     # Dynatrace logs only
│   └── zabbix/             # Zabbix via trapper items
├── patterns/               # Custom grok patterns
├── assembled/              # Generated configs (do not edit directly)
└── scripts/
    └── assemble-config.sh  # Build script
```

See [logstash-configs/README.md](./logstash-configs/README.md) for detailed configuration instructions.

## Deployment Architectures

| Architecture | Description | Link |
|--------------|-------------|------|
| aws-ec2-autoscale | Highly-available autoscaling EC2 instances behind AWS NLB with public Elastic IP. S3 bucket stores Logstash config. Rolling upgrades on config changes. | [Folder](./deployments/aws-ec2-autoscale) |
| aws-ec2-single-instance | Single EC2 instance with public Elastic IP. S3 bucket stores Logstash config. | [Folder](./deployments/aws-ec2-single-instance/) |
| azure-aci | Single Azure Container Instance with public IP. Azure Storage Fileshare stores Logstash config. | [README](./deployments/azure-aci/README.md) |

## Observability Destinations

| Destination | Description | Link |
|-------------|-------------|------|
| splunk-hec | Splunk HTTP Event Collector | [Folder](./logstash-configs/outputs/splunk-hec/) |
| azure-log-ingestion | Azure Log Analytics via Data Collection Rules | [Folder](./logstash-configs/outputs/azure-log-ingestion/) |
| dynatrace | Dynatrace metrics + logs (combined) | [Folder](./logstash-configs/outputs/dynatrace/) |
| dynatrace-metrics | Dynatrace metrics only (MINT line protocol) | [Folder](./logstash-configs/outputs/dynatrace-metrics/) |
| dynatrace-logs | Dynatrace logs only (JSON ingest) | [Folder](./logstash-configs/outputs/dynatrace-logs/) |
| zabbix | Zabbix via Dependent Items (trapper protocol) | [Folder](./logstash-configs/outputs/zabbix/) |

## Adding a New Output

1. Create `logstash-configs/outputs/<new-type>/output.conf`
2. Run `./scripts/assemble-config.sh <new-type>`
3. Deploy the generated config from `assembled/`

See [logstash-configs/README.md](./logstash-configs/README.md) for details.

## Environment Variables

### Splunk HEC

| Variable | Description | Default |
|----------|-------------|---------|
| `SPLUNK_ADDRESS` | Splunk server hostname/IP | (required) |
| `SPLUNK_PORT` | HEC port | 8088 |
| `SPLUNK_HEC_AUTH` | HEC authentication token | (required) |

### Azure Log Analytics

| Variable | Description |
|----------|-------------|
| `client_app_id` | Azure AD application ID |
| `client_app_secret` | Azure AD application secret |
| `tenant_id` | Azure AD tenant ID |
| `data_collection_endpoint` | DCE endpoint URL |
| `azure_dcr_*_id` | DCR immutable IDs |
| `azure_stream_*` | Stream names |
| `azure_cloud` | `public` or `china` |

### Dynatrace

| Variable | Description |
|----------|-------------|
| `DT_API_TOKEN` | Platform token for metrics ingest (`storage:metrics:write`) |
| `DT_LOGS_TOKEN` | Platform token for logs ingest (`storage:logs:write`); can be the same as `DT_API_TOKEN` |
| `DT_METRICS_URL` | Metrics ingest endpoint (e.g. `https://<env>.apps.dynatrace.com/api/v2/metrics/ingest`) |
| `DT_LOGS_URL` | Logs ingest endpoint (e.g. `https://<env>.apps.dynatrace.com/api/v2/logs/ingest`) |

### Zabbix

| Variable | Description | Default |
|----------|-------------|---------|
| `ZABBIX_SERVER` | Zabbix server hostname/IP | (required) |
| `ZABBIX_PORT` | Zabbix trapper port | 10051 |
| `ZABBIX_HOST_PREFIX` | Prefix for Zabbix host names | (empty) |

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the development workflow, test methodology, and architecture notes.

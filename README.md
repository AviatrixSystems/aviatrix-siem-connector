# Aviatrix Log Integration Engine

Flexible and scalable log integration between Aviatrix and 3rd party SIEM, logging, and observability tools.

The integration is built on top of Logstash with an Aviatrix-validated log parsing configuration. The engine is best-effort community supported.

## Quick Start

### 1. Build the Logstash Configuration

```bash
cd logstash-configs

# For Splunk output
./scripts/assemble-config.sh splunk-hec

# For Azure Log Analytics output
./scripts/assemble-config.sh azure-log-ingestion
```

This generates a complete configuration file in `logstash-configs/assembled/`.

### 2. Deploy

Choose a deployment architecture from `deployment-tf/` and follow its README:

| Architecture | Description |
|--------------|-------------|
| [aws-ec2-autoscale](./deployment-tf/aws-ec2-autoscale) | HA autoscaling EC2 instances behind NLB |
| [aws-ec2-single-instance](./deployment-tf/aws-ec2-single-instance) | Single EC2 instance |
| [azure-aci](./deployment-tf/azure-aci) | Azure Container Instance |

### 3. Configure Aviatrix

Point your Aviatrix Controller/CoPilot syslog export to the deployed engine's IP on port 5000 (UDP/TCP).

## Configuration Structure

```
logstash-configs/
├── inputs/                 # Syslog listener (UDP/TCP 5000)
├── filters/                # Log parsing modules
├── outputs/                # Destination-specific outputs
│   ├── splunk-hec/         # Splunk HTTP Event Collector
│   └── azure-log-ingestion/# Azure Log Analytics
├── patterns/               # Custom grok patterns
├── assembled/              # Generated configs (do not edit directly)
└── scripts/
    └── assemble-config.sh  # Build script
```

See [logstash-configs/README.md](./logstash-configs/README.md) for detailed configuration instructions.

## Deployment Architectures

| Architecture | Description | Link |
|--------------|-------------|------|
| aws-ec2-autoscale | Highly-available autoscaling EC2 instances behind AWS NLB with public Elastic IP. S3 bucket stores Logstash config. Rolling upgrades on config changes. | [Folder](./deployment-tf/aws-ec2-autoscale) |
| aws-ec2-single-instance | Single EC2 instance with public Elastic IP. S3 bucket stores Logstash config. | [Folder](./deployment-tf/aws-ec2-single-instance/) |
| azure-aci | Single Azure Container Instance with public IP. Azure Storage Fileshare stores Logstash config. | [README](./deployment-tf/azure-aci/README.md) |

## Observability Destinations

| Destination | Description | Link |
|-------------|-------------|------|
| splunk-hec | Splunk HTTP Event Collector | [Folder](./logstash-configs/outputs/splunk-hec/) |
| azure-log-ingestion | Azure Log Analytics via Data Collection Rules | [Folder](./logstash-configs/outputs/azure-log-ingestion/) |

## Supported Log Types

| Log Type | Tag | Source |
|----------|-----|--------|
| FQDN Firewall | `fqdn` | AviatrixFQDNRule |
| Controller API | `cmd` | AviatrixCMD, AviatrixAPI |
| L4 Microsegmentation | `microseg` | AviatrixGwMicrosegPacket |
| L7/TLS Inspection | `mitm` | traffic_server |
| Suricata IDS | `suricata` | suricata JSON |
| Gateway Network Stats | `gw_net_stats` | AviatrixGwNetStats |
| Gateway System Stats | `gw_sys_stats` | AviatrixGwSysStats |
| Tunnel Status | `tunnel_status` | AviatrixTunnelStatusChange |

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

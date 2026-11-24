# Aviatrix SIEM Connector

Flexible and scalable log integration between Aviatrix and 3rd party SIEM, logging, and observability tools.

The connector is built on top of Logstash with an Aviatrix-validated log parsing configuration. The engine is best-effort community supported.

## Architecture

```
                  Aviatrix Cloud Native Security Fabric
            ┌──────────────────────────────────────────┐
            │                                          │
            │  Gateways              Controller        │
            │  ├─ Distributed        ├─ API Audit      │
            │  │  Cloud Firewall     │  Logs           │
            │  ├─ Suricata IDS       ├─ Tunnel Status  │
            │  ├─ Network Stats      └─ VPN Sessions   │
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
     │  9 log types • Grok + JSON parsing • ASIM support   │
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
| **VPN** | VPN Session | VPN user connect/disconnect events |

### Pipeline Stages

1. **Parse & Tag** — Grok patterns and JSON codec extract structured fields from raw syslog. Each event is tagged by log type for downstream routing.
2. **Normalize & Convert** — Timestamps are standardized, numeric fields are type-cast, and (for Azure) ASIM schema fields are mapped. Events are not throttled or sampled; use `LOG_PROFILE` to control volume.
3. **Route** — Events are directed to the configured output based on the `LOG_PROFILE` setting (`all`, `security`, or `networking`), which controls which log categories are forwarded.

## Quick Start

### Option A: One-Command AWS Deployment (Recommended)

Deploy on ECS Fargate from AWS CloudShell using the pre-built container image:

```bash
curl -fsSL https://github.com/AviatrixSystems/aviatrix-siem-connector/releases/latest/download/quickstart.sh | bash -s -- \
  --output-type splunk-hec \
  --vpc-id vpc-xxxxxxxxxxxxxxxxx \
  --subnets subnet-aaaaaaaa,subnet-bbbbbbbb \
  --allowed-cidrs 203.0.113.10/32,203.0.113.11/32 \
  --splunk-address https://your-splunk-server \
  --splunk-hec-token your-hec-token
```

`--splunk-address` must include the scheme (`https://`); the output appends `:<port>/services/collector/event`. `--allowed-cidrs` restricts syslog sources to your gateway/controller egress IPs (default `0.0.0.0/0`).

**Other destinations:**

```bash
# Dynatrace
curl -fsSL .../quickstart.sh | bash -s -- \
  --output-type dynatrace \
  --vpc-id vpc-xxx --subnets subnet-aaa,subnet-bbb \
  --dt-metrics-url https://ENV.apps.dynatrace.com/platform/classic/environment-api/v2/metrics/ingest \
  --dt-logs-url https://ENV.apps.dynatrace.com/platform/classic/environment-api/v2/logs/ingest \
  --dt-api-token dt0s16.xxx

# Zabbix
curl -fsSL .../quickstart.sh | bash -s -- \
  --output-type zabbix \
  --vpc-id vpc-xxx --subnets subnet-aaa,subnet-bbb \
  --zabbix-server your-zabbix-server
```

The script installs Terraform if needed, creates an ECS Fargate service behind an NLB, and outputs the syslog endpoint to configure in your Aviatrix Controller.

Credentials are stored in AWS Secrets Manager and injected into the task as ECS secrets. `azure-log-ingestion` is not supported by the quickstart; use [deployments/azure-aci](./deployments/azure-aci/).

**Teardown:** `curl -fsSL .../quickstart.sh | bash -s -- --destroy`

**All options:** `curl -fsSL .../quickstart.sh | bash -s -- --help`

See [deployments/quickstart-aws/](./deployments/quickstart-aws/) for details.

### Option B: Manual Deployment

#### 1. Build the Logstash Configuration

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

#### 2. Deploy

Choose a deployment architecture from `deployments/` and follow its README:

| Architecture | Description |
|--------------|-------------|
| [aws-ecs-fargate](./deployments/aws-ecs-fargate) | ECS Fargate behind NLB, config baked into your own image |
| [aws-ec2-autoscale](./deployments/aws-ec2-autoscale) | HA autoscaling EC2 instances behind NLB |
| [aws-ec2-single-instance](./deployments/aws-ec2-single-instance) | Single EC2 instance |
| [azure-aci](./deployments/azure-aci) | Azure Container Instance |

#### 3. Configure Aviatrix

Point your Aviatrix Controller/CoPilot syslog export to the deployed engine's IP on port 5000 (UDP/TCP), or the `syslog_port` you configured.

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
| **quickstart-aws** | **One-command ECS Fargate via pre-built GHCR image. No build step required.** | [Folder](./deployments/quickstart-aws/) |
| aws-ecs-fargate | ECS Fargate behind NLB with a custom-built image (ECR); config and patterns baked in, content-hash image tags. Scalable via `desired_count`. | [Folder](./deployments/aws-ecs-fargate/) |
| aws-ec2-autoscale | Autoscaling EC2 instances behind an AWS NLB. S3 bucket stores Logstash config. Config, pattern and credential changes roll the ASG. | [Folder](./deployments/aws-ec2-autoscale) |
| aws-ec2-single-instance | Single EC2 instance with public Elastic IP. S3 bucket stores Logstash config. | [Folder](./deployments/aws-ec2-single-instance/) |
| azure-aci | Single Azure Container Instance with public IP. Azure Storage Fileshare stores Logstash config. | [README](./deployments/azure-aci/README.md) |

All AWS roots accept `allowed_syslog_cidrs` (syslog source allow-list, default `0.0.0.0/0`). The EC2 roots open no SSH by default (`ssh_allowed_cidrs = []`) and attach SSM Session Manager instead; credentials live in AWS Secrets Manager, not in user_data or plaintext task env.

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

### Common

| Variable | Description | Default |
|----------|-------------|---------|
| `LOG_PROFILE` | `all`, `security` or `networking` | `all` |
| `SYSLOG_PORT` | UDP/TCP syslog listen port | 5000 |
| `SYSLOG_TIMEZONE` | Zone for syslog timestamps that carry none (e.g. `America/New_York`) | `UTC` |

### Splunk HEC

| Variable | Description | Default |
|----------|-------------|---------|
| `SPLUNK_ADDRESS` | Splunk HEC base URL **including scheme**, e.g. `https://splunk.example.com` | (required) |
| `SPLUNK_PORT` | HEC port | 8088 |
| `SPLUNK_HEC_AUTH` | HEC authentication token | (required) |
| `FLATTEN_SURICATA` | `true` flattens nested Suricata JSON (the AWS deployments set it for splunk-hec) | unset |
| `SPLUNK_INCLUDE_SYSLOG` | `false` leaves the raw syslog line (`event.syslog`) out of payloads | `true` |

### Azure Log Analytics

| Variable | Description |
|----------|-------------|
| `client_app_id` | Azure AD application ID |
| `client_app_secret` | Azure AD application secret |
| `tenant_id` | Azure AD tenant ID |
| `data_collection_endpoint` | DCE endpoint URL |
| `azure_dcr_*_id` | DCR immutable IDs, one per type: `netsession`, `websession`, `ids`, `gw_net_stats`, `gw_sys_stats`, `cmd`, `tunnel_status`, `vpn_session` (all 8 required) |
| `azure_stream_*` | Stream names for the same 8 types |
| `azure_cloud` | `AzureCloud`, `AzureChinaCloud` or `AzureUSGovernment` |

Columns for the Azure tables and DCRs are defined once in [`deployments/azure-aci/module/ai/4-table-schemas.tf`](./deployments/azure-aci/module/ai/4-table-schemas.tf). Fields not declared there are dropped at ingestion, so add new fields there.

### Dynatrace

| Variable | Description |
|----------|-------------|
| `DT_API_TOKEN` | Platform token for metrics ingest (`storage:metrics:write`) |
| `DT_LOGS_TOKEN` | Platform token for logs ingest (`storage:logs:write`); can be the same as `DT_API_TOKEN` |
| `DT_METRICS_URL` | Metrics ingest endpoint: `https://<env>.apps.dynatrace.com/platform/classic/environment-api/v2/metrics/ingest` |
| `DT_LOGS_URL` | Logs ingest endpoint: `https://<env>.apps.dynatrace.com/platform/classic/environment-api/v2/logs/ingest` |

Metrics are named `aviatrix.gateway.*`; per-core CPU is under `aviatrix.gateway.cpu.core.{usage,idle}` with a `core` dimension. See [docs/DYNATRACE_SETUP.md](./docs/DYNATRACE_SETUP.md).

### Zabbix

| Variable | Description | Default |
|----------|-------------|---------|
| `ZABBIX_SERVER` | Zabbix server hostname/IP | (required) |
| `ZABBIX_PORT` | Zabbix trapper port | 10051 |
| `ZABBIX_HOST_PREFIX` | Prefix for Zabbix host names | (empty) |

## Upgrading / Breaking Changes

Changes in this release that can affect existing deployments, dashboards or searches:

**Parsed data (all outputs)**
- `gw_net_stats` `total_rx_rate`, `total_tx_rate`, `total_rx_tx_rate` are now floats in bytes/s (1024-based) instead of truncated integers in mixed units (`186.97Kb` was `186`, is now `191457.28`). Rescale dashboards and searches.
- `cpu_cores_parsed` now includes core `"0"`; `cpu_busy`, `cpu_aggregate_busy_*` and per-core values change for gateways whose list starts with core 0, and `cpu_core_count` goes up by 1.
- Syslog timestamps without a zone are parsed in `SYSLOG_TIMEZONE` (default `UTC`) instead of the JVM zone.
- Suricata/MITM events with invalid or truncated JSON are no longer forwarded; they get `_avx_json_parse_failure` + `unparsed`. Grok misses get `_avx_grok_failure_<type>`; untyped events get `unparsed`. Absent MITM fields are omitted instead of holding literal `%{...}` text.
- Tunnel status events gain `gateway` (source gateway name); V2.5 `AviatrixAPI` events gain `controller_ip` and `gw_hostname`, and `username`/`args`/`result` split at the first occurrence of each key.
- Docs correction: microseg events are not throttled (the throttle filter was removed in an earlier release; the old "2 logs/minute per connection" claim was stale). Size SIEM ingest for full L4 volume.

**Outputs**
- Splunk (microseg, fqdn, cmd, gw_net_stats, tunnel_status, vpn_session): absent fields are omitted, values keep native JSON types (numbers/booleans instead of strings), tunnel `host` is the gateway name. New `SPLUNK_INCLUDE_SYSLOG` (default `true`).
- `webhook-test` now sends Splunk HEC-shaped payloads (`sourcetype` replaces `type`) and honors `LOG_PROFILE`.
- Dynatrace: per-core and aggregate-core CPU moved from `aviatrix.gateway.cpu.{idle,usage}` (with `core`) to `aviatrix.gateway.cpu.core.{idle,usage}`. `dynatrace-logs` now forwards `vpn_session` and the extra MITM attributes.
- Zabbix cumulative counters are sent as integers (rounded to whole bytes).

**AWS deployments**
- SSH is no longer open to `0.0.0.0/0`: `ssh_allowed_cidrs` defaults to `[]` (no rule); use SSM Session Manager or set the variable. An empty `ssh_key_name` means no key pair.
- Credentials move to Secrets Manager (EC2 `avxlog-<suffix>-runtime`, ECS `avxlog-<suffix>-config`). The first apply replaces the single instance, rolls the ASG, and creates a new ECS task definition. On ECS, `azure-log-ingestion` env names are no longer uppercased.
- EC2 TLS mode no longer uses docker-compose: the output's `docker_run.tftpl` runs Logstash and stunnel runs with `--network host`.
- `zabbix` and `azure-log-ingestion` on EC2 fail at plan unless `logstash_config_variables.logstash_image` names an image with the plugin (e.g. built from `logstash-configs/outputs/zabbix/Containerfile`). Do not use the GHCR image for this.
- Dynatrace EC2 templates target `https://<env>.apps.dynatrace.com/platform/classic/...`; `dt_region = "live"` is treated as `apps`. Override with `dt_region`, `dt_metrics_url` or `dt_logs_url`.
- Docker run templates quote `-e` values. `syslog_protocol` must be `tcp` or `udp`; `syslog_port != 5000` is rejected unless the assembled config honors `SYSLOG_PORT` (reassemble).
- Autoscale: ELB health checks with `health_check_grace_period` (default 600s); target group `deregistration_delay` 60s (was 300) with connection termination.
- Single instance ignores AMI changes (`ignore_changes = [ami]`); pin `ami_id` or use `terraform apply -replace`. The AMI filter now excludes minimal images.
- New optional variables: `allowed_syslog_cidrs`, `ssh_allowed_cidrs`, `ami_id`, `health_check_grace_period`, `deregistration_delay`.
- The unused S3 access point is destroyed and the bucket gets a public access block.
- Fargate/quickstart set `LS_JAVA_OPTS` to half the task memory. `build-and-push.sh` tags images `cfg-<hash>` (not `latest`) and always reassembles. `quickstart.sh` pins `latest` to the resolved release tag and rejects `azure-log-ingestion`.

**Azure deployments**
- `container_image` has no default and `docker.elastic.co/logstash/*` images are rejected.
- `client_app_id`, `client_app_secret`, `tenant_id` default to `null` and must be GUIDs; with `use_existing_spn = true` (default) all three are required.
- `azure_cloud`: deploy-public accepts `AzureCloud` or `AzureUSGovernment` (US Gov also switches the providers); deploy-china accepts only `AzureChinaCloud`.
- `module/ai` dropped the `log_analytics_resource_group_name` input and needs Terraform >= 1.3 plus the `hashicorp/time` provider (`terraform init` first).
- Next apply replaces the container group (secret moved to secure env; the public IP may change, the FQDN does not) and both config share files once, grows share quotas to 5 GB, and adds columns to the netsession/websession/ids tables and DCRs. With `use_existing_spn = false` the generated SPN secret is replaced and rotates every `spn_secret_rotation_days` (180).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the development workflow, test methodology, and architecture notes.

## License

This project is licensed under the [Elastic License 2.0](./LICENSE). You may use,
copy, modify, and distribute the software, subject to the limitations in the license
(notably, you may not offer it as a hosted/managed service).

Aviatrix brand assets (logos and similar, including those shipped with the separately
developed status sidecar) are proprietary to Aviatrix Systems, Inc. and are **not** covered
by the Elastic License 2.0. See [TRADEMARK.md](./TRADEMARK.md) for trademark usage guidelines.

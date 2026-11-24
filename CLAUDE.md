# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Aviatrix SIEM Connector** - an ETL layer built on Logstash that normalizes Aviatrix syslog data and forwards it to various SIEM/observability platforms. The engine receives syslog on UDP/TCP port 5000, parses multiple Aviatrix log types using grok patterns, and routes to configurable outputs.

## Architecture

```
Aviatrix Gateways/Controllers
         │
         ▼ (syslog UDP/TCP 5000)
    ┌─────────────────────────────────────┐
    │         Logstash Pipeline           │
    │  ┌─────────────────────────────┐    │
    │  │ Input: UDP/TCP 5000         │    │
    │  └──────────┬──────────────────┘    │
    │             ▼                       │
    │  ┌─────────────────────────────┐    │
    │  │ Filters: Grok parsing by    │    │
    │  │ log type (tag-based routing)│    │
    │  └──────────┬──────────────────┘    │
    │             ▼                       │
    │  ┌─────────────────────────────┐    │
    │  │ Outputs: Splunk HEC, Azure  │    │
    │  │ Log Analytics, Elasticsearch│    │
    │  └─────────────────────────────┘    │
    └─────────────────────────────────────┘
```

### Log Types Processed

| Tag | Log Type | Source |
|-----|----------|--------|
| `fqdn` | DNS/FQDN Firewall rules | `AviatrixFQDNRule` |
| `cmd` | Controller API calls (V1/V2.5) | `AviatrixCMD`, `AviatrixAPI` |
| `microseg` | L4 microsegmentation (eBPF) | `AviatrixGwMicrosegPacket` |
| `mitm` | L7/TLS inspection | `traffic_server` JSON |
| `suricata` | IDS/IPS alerts | `suricata` JSON |
| `gw_net_stats` | Gateway network stats | `AviatrixGwNetStats` |
| `gw_sys_stats` | Gateway system stats | `AviatrixGwSysStats` |
| `tunnel_status` | Tunnel state changes | `AviatrixTunnelStatusChange` |
| `vpn_session` | VPN connect/disconnect | `AviatrixVPNSession` |

### Key Processing Patterns

- **Tag-based routing**: Filters add tags; subsequent filters exclude already-tagged events
- **Break on match**: Grok uses `break_on_match => true` to stop after first successful pattern
- **Metadata fields**: Uses `[@metadata]` namespace for intermediate processing
- **No throttling or cloning**: every parsed event is forwarded once (subject to `LOG_PROFILE`). MITM events are mapped into microseg-style fields in place, not cloned
- **Failure tags**: grok misses add `_avx_grok_failure_<type>`; invalid Suricata/MITM JSON loses its type tag and gets `_avx_json_parse_failure`; `97-tag-unparsed.conf` tags anything with no type tag as `unparsed`. Outputs route on type tags, so these are not forwarded
- **Log profiles**: Output blocks are gated by `LOG_PROFILE` env var (`all`/`security`/`networking`) to control which log types are forwarded. See CONTRIBUTING.md for the full profile specification and implementation pattern

## Directory Structure

```
logstash-configs/
├── inputs/                              # Modular input configs
│   └── 00-syslog-input.conf             # UDP/TCP ${SYSLOG_PORT:5000} syslog input
├── filters/                             # Modular filter configs (processed in order)
│   ├── 10-microseg.conf                 # L4 microseg parsing (legacy + 8.2)
│   ├── 11-l7-dcf.conf                   # L7 DCF/MITM parsing
│   ├── 12-suricata.conf                 # Suricata IDS parsing (+ HEC payload)
│   ├── 13-fqdn.conf                     # FQDN firewall rule parsing
│   ├── 14-cmd.conf                      # Controller CMD/API parsing
│   ├── 15-gateway-stats.conf            # gw_net_stats, gw_sys_stats
│   ├── 16-tunnel-status.conf            # Tunnel state changes
│   ├── 17-cpu-cores-parse.conf          # CPU cores protobuf text → structured JSON
│   ├── 18-vpn-session.conf              # VPN session connect/disconnect
│   ├── 90-timestamp.conf                # Date normalization (SYSLOG_TIMEZONE, default UTC)
│   ├── 94-save-raw-net-rates.conf       # Raw net-rate strings → [@metadata]
│   ├── 95-field-conversion.conf         # Type conversions (net rates → float bytes/s)
│   ├── 96-sys-stats-hec.conf            # gw_sys_stats HEC payload builder
│   └── 97-tag-unparsed.conf             # Tag events with no type tag as "unparsed"
├── outputs/                             # Output-specific configs
│   ├── splunk-hec/
│   │   ├── output.conf                  # Splunk HEC output
│   │   ├── docker_run.tftpl             # Docker run template
│   │   └── README.md                    # Splunk setup instructions
│   ├── dynatrace/, dynatrace-metrics/, dynatrace-logs/, zabbix/
│   ├── webhook-test/                    # Local test sink (Splunk HEC-shaped payloads)
│   ├── ci-test/                         # CI file output
│   └── azure-log-ingestion/
│       ├── output.conf                  # Azure Log Analytics output (ASIM-normalized)
│       ├── docker_run.tftpl             # Docker run template
│       ├── asim-parsers/                # KQL ASIM parser files for Sentinel
│       │   ├── vimNetworkSessionAviatrixGateway.kql   # L4 microseg parser
│       │   ├── vimWebSessionAviatrixGateway.kql       # L7 MITM parser
│       │   └── vimNetworkSessionAviatrixSuricata.kql  # Suricata IDS parser
│       └── _sample*.json                # Sample outputs (Microseg, Suricata, WebSession)
├── patterns/
│   └── avx.conf                         # Enhanced grok patterns
├── assembled/                           # Auto-generated full configs
│   ├── splunk-hec-full.conf             # Complete Splunk config
│   └── azure-log-ingestion-full.conf    # Complete Azure config
├── scripts/
│   └── assemble-config.sh               # Config assembly script

deployments/
├── modules/
│   ├── aws-logstash/                    # Shared AWS module (S3, IAM, SG, AMI, Secrets Manager, user_data)
│   └── tls-certs/                       # TLS CA/server certs in Secrets Manager
├── aws-ec2-single-instance/             # Single EC2 + S3 config bucket
├── aws-ec2-autoscale/                   # NLB + ASG with rolling updates
├── aws-ecs-fargate/                     # ECS Fargate + NLB, config baked into image
├── quickstart-aws/                      # One-command Fargate using the GHCR image (quickstart.sh)
└── azure-aci/                           # Azure Container Instance deployment
    ├── deploy-public/                   # Azure Public Cloud / US Gov
    ├── deploy-china/                    # Azure China Cloud
    └── module/                          # Reusable TF modules
        └── ai/4-table-schemas.tf        # Single source of truth for LA table + DCR columns

test-tools/
├── sample-logs/
│   ├── test-samples.log                 # Curated test samples for all log types
│   ├── stream-logs.py                   # Syslog streamer for testing
│   ├── update-timestamps.py             # Rewrite all timestamps to current UTC window
│   └── generate-current-samples.sh      # Wrapper around update-timestamps.py
├── golden/                              # Golden I/O tests: golden.py + expected/<output>/<case>.json
├── ci/                                  # CI helpers (output-env-vars.sh, validate-output.sh)
├── syslog-collector/                    # Internal only: gitignored, not in a fresh clone
└── webhook-viewer/
    └── local/
        └── run.sh                       # Start/stop local webhook viewer
```

## Working with Logstash Configs

### Modular Configuration (Recommended)

The configuration is now modularized into separate input, filter, and output files:

1. **Inputs** (`inputs/`): Syslog listener configuration
2. **Filters** (`filters/`): Parsing and transformation logic, numbered for execution order
3. **Outputs** (`outputs/<type>/`): Destination-specific output configuration

To assemble a complete config for deployment:

```bash
cd logstash-configs
./scripts/assemble-config.sh splunk-hec           # Creates assembled/splunk-hec-full.conf
./scripts/assemble-config.sh azure-log-ingestion  # Creates assembled/azure-log-ingestion-full.conf
```

### Adding a New Output Type

1. Create `outputs/<new-type>/output.conf` with the output block
2. Run `./scripts/assemble-config.sh <new-type>` to generate the full config
3. Validate syntax with dummy env vars (see Testing Workflow step 3); add the type to `test-tools/ci/output-env-vars.sh`

### Modifying Filters

Edit the appropriate file in `filters/`. Changes apply to ALL output types when reassembled:
- Add new log types: Create a new `filters/1X-<type>.conf`
- Modify parsing: Edit the relevant filter file
- Filters that need `unix_time` or converted types must be numbered > 95

### Pattern File Location

Configs reference patterns at `/usr/share/logstash/patterns` (deployment). Custom patterns are in `patterns/avx.conf` with support for:
- Legacy 7.x log formats
- 8.2+ session fields (SESSION_EVENT, SESSION_BYTE_COUNT, etc.)

### Environment Variables

All output types use:
- `LOG_PROFILE` - Which log types to forward: `all` (default), `security`, or `networking`
- `SYSLOG_PORT` - Listen port for the UDP/TCP input (default: 5000)
- `SYSLOG_TIMEZONE` - Zone for syslog timestamps that carry none (default: `UTC`)
- `FLATTEN_SURICATA` - `true` flattens nested Suricata JSON (set for splunk-hec)

Splunk configs use:
- `SPLUNK_ADDRESS` - Splunk HEC base URL including scheme, e.g. `https://splunk.example.com` (the output appends `:${SPLUNK_PORT}/services/collector/event`)
- `SPLUNK_PORT` - HEC port (default: 8088)
- `SPLUNK_HEC_AUTH` - HEC authentication token
- `SPLUNK_INCLUDE_SYSLOG` - `false` omits the raw syslog line (`event.syslog`) from payloads (default: `true`)

Dynatrace configs use `DT_METRICS_URL`, `DT_LOGS_URL` (`https://<env>.apps.dynatrace.com/platform/classic/environment-api/v2/{metrics,logs}/ingest`), `DT_API_TOKEN`, `DT_LOGS_TOKEN`. Zabbix uses `ZABBIX_SERVER`, `ZABBIX_PORT`, `ZABBIX_HOST_PREFIX`. `webhook-test` uses `WEBHOOK_URL`.

Azure configs use:
- `client_app_id`, `client_app_secret`, `tenant_id` - Service principal credentials
- `data_collection_endpoint` - DCE endpoint URL
- `azure_dcr_netsession_id` - DCR for L4 microseg (ASIM NetworkSession)
- `azure_dcr_websession_id` - DCR for L7 MITM (ASIM WebSession)
- `azure_dcr_ids_id` - DCR for Suricata IDS (ASIM NetworkSession)
- `azure_dcr_gw_net_stats_id`, `azure_dcr_gw_sys_stats_id`, `azure_dcr_cmd_id`, `azure_dcr_tunnel_status_id`, `azure_dcr_vpn_session_id` - DCRs for non-ASIM log types
- `azure_stream_netsession`, `azure_stream_websession`, `azure_stream_ids` - ASIM stream names
- `azure_stream_gw_net_stats`, `azure_stream_gw_sys_stats`, `azure_stream_cmd`, `azure_stream_tunnel_status`, `azure_stream_vpn_session` - Non-ASIM stream names
- All 8 DCR/stream pairs are required whatever `LOG_PROFILE` is (no defaults)
- `azure_cloud` - "AzureCloud", "AzureChinaCloud", or "AzureUSGovernment"

## ASIM Normalization (Azure Only)

The 3 security log types are ASIM-normalized for Azure Sentinel integration. ASIM field mapping is performed in Logstash (in the Azure output config), not in KQL transforms.

### Azure Table Mapping

| Log Type | Azure Table | ASIM Schema | EventType |
|---|---|---|---|
| L4 Microseg | `AviatrixNetworkSession_CL` | NetworkSession | `NetworkSession` |
| L7 MITM/DCF | `AviatrixWebSession_CL` | WebSession | `HTTPsession` |
| Suricata IDS | `AviatrixIDS_CL` | NetworkSession | `IDS` |
| GwNetStats | `AviatrixGwNetStats_CL` | (none) | - |
| GwSysStats | `AviatrixGwSysStats_CL` | (none) | - |
| Cmd | `AviatrixCmd_CL` | (none) | - |
| TunnelStatus | `AviatrixTunnelStatus_CL` | (none) | - |
| VpnSession | `AviatrixVPNSession_CL` | (none) | - |

Columns for all 8 tables and DCRs come from `deployments/azure-aci/module/ai/4-table-schemas.tf`; a field missing there is dropped at ingestion, so add new fields there.

### ASIM Field Patterns

All ASIM-normalized events include:
- `EventVendor` = "Aviatrix", `EventProduct` = "Distributed Cloud Firewall" or "Suricata IDS"
- `EventSchema`, `EventSchemaVersion` ("0.2.7"), `EventType`, `EventCount`
- `DvcAction` (Allow/Deny/Drop), `DvcOriginalAction`, `EventResult` (Success/Failure)
- `SrcIpAddr`, `DstIpAddr`, `SrcPortNumber`, `DstPortNumber`, `NetworkProtocol`

Suricata IDS additionally includes threat fields: `ThreatName`, `ThreatId`, `ThreatCategory`, `ThreatRiskLevel`

Original Aviatrix-specific fields are preserved alongside ASIM fields.

### KQL ASIM Parsers

Three parser files in `logstash-configs/outputs/azure-log-ingestion/asim-parsers/`:
- `vimNetworkSessionAviatrixGateway.kql` - L4 microseg → `_Im_NetworkSession`
- `vimWebSessionAviatrixGateway.kql` - L7 MITM → `_Im_WebSession`
- `vimNetworkSessionAviatrixSuricata.kql` - Suricata IDS → `_Im_NetworkSession`

Deploy as saved functions via Azure CLI (see deployment instructions in each .kql file).

## Terraform Deployments

### AWS Deployment

```bash
cd deployments/aws-ec2-single-instance  # or aws-ec2-autoscale, aws-ecs-fargate
terraform init
terraform plan
terraform apply
```

- EC2 credentials are rendered into a per-deployment Secrets Manager secret (`avxlog-<suffix>-runtime`) fetched at boot; ECS injects `logstash_config_variables` from an `avxlog-<suffix>-config` secret.
- SSH is closed by default (`ssh_allowed_cidrs = []`); use SSM Session Manager. Restrict syslog sources with `allowed_syslog_cidrs` (default `0.0.0.0/0`).
- `zabbix` and `azure-log-ingestion` on EC2 require `logstash_config_variables.logstash_image` (an image with the plugin).
- EC2 TLS mode runs the output's `docker_run.tftpl` plus a stunnel container on the host network (no docker-compose).
- Autoscale: config, pattern or credential changes roll the ASG via instance refresh (ELB health checks).

### Azure ACI Deployment

Prerequisites:
1. Tables and DCRs are created by Terraform from `module/ai/4-table-schemas.tf` (the single column list; add new fields there). For manual creation see the helper in `logstash-configs/outputs/azure-log-ingestion/README.md`.

2. Deploy:
```bash
cd deployments/azure-aci/deploy-public  # or deploy-china
cp terraform.tfvars.sample terraform.tfvars
# Edit terraform.tfvars
terraform init && terraform apply
```

## Test Tools

### Syslog Collector (`test-tools/syslog-collector/`)

Internal tool for capturing live Aviatrix syslog on an EC2 host. It is gitignored and not present in a fresh clone; if you have a local copy, deploy it with `terraform apply` in that directory and point gateways at `<public-ip>:514`.

## Testing Logstash Configurations

When editing or building Logstash configurations, use the following test workflow:

### Test Components

1. **Sample Logs** (`test-tools/sample-logs/`)
   - `test-samples.log` - Curated samples of each supported log type
   - `stream-logs.py` - Python script to stream logs to syslog endpoint
   - `update-timestamps.py` - Rewrites all 11 timestamp formats to a UTC window around now
   - `generate-current-samples.sh` - Wrapper that calls update-timestamps.py
   - Includes both legacy 7.x and 8.2+ format variations
   - 54 log lines → 52 events (suricata `Notice` and `event_type=stats` lines are dropped). Per tag: microseg 9, mitm 12, suricata 1, cmd 5, fqdn 3, gw_net_stats 7, gw_sys_stats 7, tunnel_status 4, vpn_session 4, unparsed 0

   ```bash
   # Refresh timestamps into an untracked copy (--overwrite rewrites the tracked file; CI only)
   ./generate-current-samples.sh -o /tmp/samples-now.log
   ./stream-logs.py -f /tmp/samples-now.log    # Stream all to localhost:5000
   ./stream-logs.py --port 5002 -v             # Stream to port 5002, verbose
   ./stream-logs.py --filter microseg          # Only microseg logs
   ./stream-logs.py --target 10.0.0.5 --tcp    # TCP to custom host
   ./stream-logs.py --loop --delay 1           # Continuous replay
   ./stream-logs.py --list-types               # Show available filters
   ```

   - `edge-cases.log` - variants, release-specific formats (9.0, 10.1), known bugs and negative cases, sourced from cloudn, CoPilot/oteld and the lab Splunk. Read only by the golden tests, not the E2E count check
   - Every sample line has a `# @case <id> [avx=<first release>] [until=<last release>]` annotation

2. **Golden I/O tests** (`test-tools/golden/`, see its README)
   - Field-by-field expected output per case for `parsed`, `splunk-hec`, `dynatrace-logs`, `azure-log-ingestion`
   - `./golden.py check [--output X] [--case REGEX] [--avx 10.1]` diffs the engine against `expected/`; `generate` accepts new behavior after review
   - `./golden.py azure-columns` flags fields the Azure DCR would drop and column type mismatches
   - Engine-agnostic: the Fluent Bit port is tested against the same expected files
   - Needs ~1 GB free in the Docker/Podman VM (test JVM is capped at 512 MB)

3. **Webhook Viewer** (`test-tools/webhook-viewer/local/`)
   - Local Docker-based webhook endpoint for testing HTTP outputs
   - Start: `cd test-tools/webhook-viewer/local && ./run.sh`
   - Access UI: http://localhost:8080
   - Create a session to get a unique webhook URL

4. **Syslog Collector** (`test-tools/syslog-collector/`, internal, not shipped)
   - AWS EC2 deployment for capturing live Aviatrix logs

### Testing Workflow

1. **Edit filter/pattern files** in `logstash-configs/filters/` or `patterns/`

2. **Assemble the config** for your target output:
   ```bash
   cd logstash-configs
   ./scripts/assemble-config.sh splunk-hec
   ```

3. **Validate syntax** (unset `${VAR}`s fail compilation, so pass the CI dummies):
   ```bash
   docker run --rm -v "$(pwd)/assembled:/config" -v "$(pwd)/patterns:/usr/share/logstash/patterns" \
     $(../test-tools/ci/output-env-vars.sh splunk-hec) \
     docker.elastic.co/logstash/logstash:8.16.2 \
     logstash -f /config/splunk-hec-full.conf --config.test_and_exit
   ```

4. **Test with sample logs and webhook viewer**:
   ```bash
   # Terminal 1: Start webhook viewer
   cd test-tools/webhook-viewer/local && ./run.sh

   # Terminal 2: Run Logstash with the webhook-test output
   #   (-e WEBHOOK_URL=http://host.docker.internal:8080/<session-id>; see CONTRIBUTING.md)
   # Terminal 3: Stream test logs
   cd test-tools/sample-logs
   ./stream-logs.py --port 5002 --filter microseg -v     # Verbose, microseg only
   ```

5. **Verify parsed output** in the webhook viewer UI - check that fields are extracted correctly

### Using Playwright MCP for Automated Webhook Inspection

Claude Code can use the Playwright MCP to interact with the webhook viewer UI programmatically:

1. **Navigate to webhook viewer**:
   ```
   mcp__playwright__browser_navigate → http://localhost:8080
   ```

2. **Create a new session**:
   ```
   mcp__playwright__browser_click → "New URL" button
   mcp__playwright__browser_click → "Create" button
   ```

3. **Get webhook URL from UI**: The URL appears in the page snapshot (e.g., `http://localhost:8080/<session-id>`)

4. **Send test data**: Use curl or stream-logs.py to send data through Logstash to the webhook

5. **Inspect captured requests**:
   ```
   mcp__playwright__browser_snapshot → Shows request details including:
   - Request body (parsed JSON)
   - HTTP headers
   - Method, path, timing
   - Source IP
   ```

This enables Claude to:
- Automatically verify Logstash output format after config changes
- Check that grok patterns extract fields correctly
- Validate JSON structure of transformed events
- Debug parsing issues by comparing input samples to output

### Adding New Test Samples

When adding support for new log types or encountering parsing issues:
1. Collect real examples from production logs (or the internal syslog-collector)
2. Add representative samples to `test-tools/sample-logs/test-samples.log`
3. Include comments explaining the log type and any variations
4. Test the full pipeline before committing

## Known Issues

- **Splunk SSL**: Uses `ssl_verification_mode => "none"` - needs proper certs for production

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Aviatrix Log Integration Engine** - an ETL layer built on Logstash that normalizes Aviatrix syslog data and forwards it to various SIEM/observability platforms. The engine receives syslog on UDP/TCP port 5000, parses multiple Aviatrix log types using grok patterns, and routes to configurable outputs.

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

### Key Processing Patterns

- **Tag-based routing**: Filters add tags; subsequent filters exclude already-tagged events
- **Break on match**: Grok uses `break_on_match => true` to stop after first successful pattern
- **Metadata fields**: Uses `[@metadata]` namespace for intermediate processing
- **Microseg throttling**: Max 2 logs/minute per connection (configurable via throttle filter)
- **MITM cloning**: MITM events are cloned to generate both microseg and FQDN events
- **Log profiles**: Output blocks are gated by `LOG_PROFILE` env var (`all`/`security`/`networking`) to control which log types are forwarded. See CONTRIBUTING.md for the full profile specification and implementation pattern

## Directory Structure

```
logstash-configs/
├── inputs/                              # Modular input configs
│   └── 00-syslog-input.conf             # UDP/TCP 5000 syslog input
├── filters/                             # Modular filter configs (processed in order)
│   ├── 10-fqdn.conf                     # FQDN firewall rule parsing
│   ├── 11-cmd.conf                      # Controller CMD/API parsing
│   ├── 12-microseg.conf                 # L4 microseg parsing (legacy + 8.2)
│   ├── 13-l7-dcf.conf                   # L7 DCF/MITM parsing
│   ├── 14-suricata.conf                 # Suricata IDS parsing
│   ├── 15-gateway-stats.conf            # gw_net_stats, gw_sys_stats
│   ├── 16-tunnel-status.conf            # Tunnel state changes
│   ├── 17-cpu-cores-parse.conf          # CPU cores protobuf text → structured JSON
│   ├── 80-throttle.conf                 # Microseg throttling
│   ├── 90-timestamp.conf                # Date normalization
│   ├── 95-field-conversion.conf         # Type conversions
│   └── 96-sys-stats-hec.conf            # gw_sys_stats HEC payload builder
├── outputs/                             # Output-specific configs
│   ├── splunk-hec/
│   │   ├── output.conf                  # Splunk HEC output
│   │   ├── docker_run.tftpl             # Docker run template
│   │   └── README.md                    # Splunk setup instructions
│   └── azure-log-ingestion/
│       ├── output.conf                  # Azure Log Analytics output (ASIM-normalized)
│       ├── docker_run.tftpl             # Docker run template
│       ├── asim-parsers/                # KQL ASIM parser files for Sentinel
│       │   ├── vimNetworkSessionAviatrixGateway.kql   # L4 microseg parser
│       │   ├── vimWebSessionAviatrixGateway.kql       # L7 MITM parser
│       │   └── vimNetworkSessionAviatrixSuricata.kql  # Suricata IDS parser
│       └── _sample*.json                # Sample output files for testing
├── patterns/
│   └── avx.conf                         # Enhanced grok patterns
├── assembled/                           # Auto-generated full configs
│   ├── splunk-hec-full.conf             # Complete Splunk config
│   └── azure-log-ingestion-full.conf    # Complete Azure config
├── scripts/
│   └── assemble-config.sh               # Config assembly script
└── output_loganalytics_sentinel_dcr/    # Azure Sentinel DCR templates

deployments/
├── modules/
│   └── aws-logstash/                    # Shared AWS module (S3, IAM, SG, AMI, user_data)
├── aws-ec2-single-instance/             # Single EC2 + S3 config bucket
├── aws-ec2-autoscale/                   # NLB + ASG with rolling updates
└── azure-aci/                           # Azure Container Instance deployment
    ├── deploy-public/                   # Azure Public Cloud
    ├── deploy-china/                    # Azure China Cloud
    └── module/                          # Reusable TF modules

test-tools/
├── sample-logs/
│   ├── test-samples.log                 # Curated test samples for all log types
│   ├── stream-logs.py                   # Syslog streamer for testing
│   ├── update-timestamps.py             # Rewrite all timestamps to current UTC window
│   └── generate-current-samples.sh      # Wrapper: refresh timestamps in-place
├── syslog-collector/                    # AWS EC2 syslog capture tool
│   ├── main.tf, variables.tf, etc.      # Terraform deployment
│   └── user_data.sh                     # Container setup
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
3. Test with Logstash: `logstash -f assembled/<new-type>-full.conf --config.test_and_exit`

### Modifying Filters

Edit the appropriate file in `filters/`. Changes apply to ALL output types when reassembled:
- Add new log types: Create a new `filters/1X-<type>.conf`
- Modify parsing: Edit the relevant filter file
- Change throttling: Edit `filters/80-throttle.conf`

### Pattern File Location

Configs reference patterns at `/usr/share/logstash/patterns` (deployment). Custom patterns are in `patterns/avx.conf` with support for:
- Legacy 7.x log formats
- 8.2+ session fields (SESSION_EVENT, SESSION_BYTE_COUNT, etc.)

### Environment Variables

All output types use:
- `LOG_PROFILE` - Which log types to forward: `all` (default), `security`, or `networking`

Splunk configs use:
- `SPLUNK_ADDRESS` - Splunk server hostname/IP
- `SPLUNK_PORT` - HEC port (default: 8088)
- `SPLUNK_HEC_AUTH` - HEC authentication token

Azure configs use:
- `client_app_id`, `client_app_secret`, `tenant_id` - Service principal credentials
- `data_collection_endpoint` - DCE endpoint URL
- `azure_dcr_netsession_id` - DCR for L4 microseg (ASIM NetworkSession)
- `azure_dcr_websession_id` - DCR for L7 MITM (ASIM WebSession)
- `azure_dcr_ids_id` - DCR for Suricata IDS (ASIM NetworkSession)
- `azure_dcr_gw_net_stats_id`, `azure_dcr_gw_sys_stats_id`, `azure_dcr_cmd_id`, `azure_dcr_tunnel_status_id` - DCRs for non-security log types
- `azure_stream_netsession`, `azure_stream_websession`, `azure_stream_ids` - ASIM stream names
- `azure_stream_gw_net_stats`, `azure_stream_gw_sys_stats`, `azure_stream_cmd`, `azure_stream_tunnel_status` - Non-security stream names
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
cd deployments/aws-ec2-single-instance  # or aws-ec2-autoscale
terraform init
terraform plan
terraform apply
```

Config changes trigger rolling instance refresh via S3 bucket updates.

### Azure ACI Deployment

Prerequisites:
1. Tables are auto-created by Terraform (`3-log-analytics-tables.tf`). For manual creation:
```bash
az monitor log-analytics workspace table create \
    --resource-group <rg> --workspace-name <ws> \
    --name "AviatrixNetworkSession_CL" \
    --columns TimeGenerated=datetime EventVendor=string SrcIpAddr=string DstIpAddr=string ...

az monitor log-analytics workspace table create \
    --resource-group <rg> --workspace-name <ws> \
    --name "AviatrixWebSession_CL" \
    --columns TimeGenerated=datetime EventVendor=string DstFqdn=string Url=string ...

az monitor log-analytics workspace table create \
    --resource-group <rg> --workspace-name <ws> \
    --name "AviatrixIDS_CL" \
    --columns TimeGenerated=datetime EventVendor=string ThreatName=string alert=dynamic ...
```

2. Deploy:
```bash
cd deployments/azure-aci/deploy-public  # or deploy-china
cp terraform.tfvars.sample terraform.tfvars
# Edit terraform.tfvars
terraform init && terraform apply
```

## Test Tools

### Syslog Collector (`test-tools/syslog-collector/`)

A standalone AWS EC2 deployment for collecting sample syslog data. Use this to capture real Aviatrix logs for testing ETL configurations.

**Deploy:**
```bash
cd test-tools/syslog-collector
cp terraform.tfvars.example terraform.tfvars  # Edit with your settings
terraform init && terraform apply
```

**Access:**
- Syslog endpoint: `<public-ip>:514` (UDP/TCP)
- Web UI: `http://<public-ip>` (browse/download logs)
- SSH: `ssh -i ~/Documents/keys/<key>.pem ec2-user@<public-ip>`

**Collect logs:**
1. Point Aviatrix controller/gateways to send syslog to the collector IP
2. Let logs accumulate
3. Download via web UI or SSH: `sudo ls /opt/syslog-collector/logs/`

**Cleanup:**
```bash
terraform destroy
```

## Testing Logstash Configurations

When editing or building Logstash configurations, use the following test workflow:

### Test Components

1. **Sample Logs** (`test-tools/sample-logs/`)
   - `test-samples.log` - Curated samples of each supported log type
   - `stream-logs.py` - Python script to stream logs to syslog endpoint
   - `update-timestamps.py` - Rewrites all 9 timestamp formats to a UTC window around now
   - `generate-current-samples.sh` - Wrapper that calls update-timestamps.py
   - Includes both legacy 7.x and 8.2+ format variations

   ```bash
   ./generate-current-samples.sh --overwrite   # Refresh timestamps to now (UTC)
   ./stream-logs.py                            # Stream all to localhost:5000
   ./stream-logs.py --port 5002 -v             # Stream to port 5002, verbose
   ./stream-logs.py --filter microseg          # Only microseg logs
   ./stream-logs.py --target 10.0.0.5 --tcp    # TCP to custom host
   ./stream-logs.py --loop --delay 1           # Continuous replay
   ./stream-logs.py --list-types               # Show available filters
   ```

2. **Webhook Viewer** (`test-tools/webhook-viewer/local/`)
   - Local Docker-based webhook endpoint for testing HTTP outputs
   - Start: `cd test-tools/webhook-viewer/local && ./run.sh`
   - Access UI: http://localhost:8080
   - Create a session to get a unique webhook URL

3. **Syslog Collector** (`test-tools/syslog-collector/`)
   - AWS EC2 deployment for capturing live Aviatrix logs
   - Use to collect real-world samples for test-samples.log

### Testing Workflow

1. **Edit filter/pattern files** in `logstash-configs/filters/` or `patterns/`

2. **Assemble the config** for your target output:
   ```bash
   cd logstash-configs
   ./scripts/assemble-config.sh splunk-hec
   ```

3. **Validate syntax**:
   ```bash
   docker run --rm -v $(pwd)/assembled:/config -v $(pwd)/patterns:/usr/share/logstash/patterns \
     docker.elastic.co/logstash/logstash:8.11.0 \
     logstash -f /config/splunk-hec-full.conf --config.test_and_exit
   ```

4. **Test with sample logs and webhook viewer**:
   ```bash
   # Terminal 1: Start webhook viewer
   cd test-tools/webhook-viewer/local && ./run.sh

   # Terminal 2: Run Logstash container (with HTTP output to webhook)
   # Terminal 3: Stream test logs
   cd test-tools/sample-logs
   ./stream-logs.py --filter microseg -v     # Verbose, microseg only
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
1. Collect real examples using syslog-collector or from production logs
2. Add representative samples to `test-tools/sample-logs/test-samples.log`
3. Include comments explaining the log type and any variations
4. Test the full pipeline before committing

## Known Issues

- **Splunk SSL**: Uses `ssl_verification_mode => "none"` - needs proper certs for production

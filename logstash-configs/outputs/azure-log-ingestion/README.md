# Azure Log Analytics Output

This output configuration sends parsed Aviatrix logs to Azure Log Analytics via the Data Collection Rules (DCR) API using the Microsoft Sentinel Logstash plugin.

Security log types (L4 microseg, L7 MITM, Suricata IDS) are ASIM-normalized in the output config. Non-security types pass through unchanged.

## Prerequisites

### 1. Build a Custom Logstash Image

The stock Elastic image does NOT include the Sentinel plugin. You must build a custom image. See `deployments/azure-aci/logstash-container-build/README.md`.

### 2. Create Custom Log Analytics Tables

Tables are auto-created by Terraform (`deployments/azure-aci/`), which is the recommended path.

For a manual setup, every table and DCR stream must declare **every** column the
output sends: the DCR silently drops any undeclared field. The authoritative
column lists live in one file,
[`deployments/azure-aci/module/ai/4-table-schemas.tf`](../../../deployments/azure-aci/module/ai/4-table-schemas.tf)
(keys: `netsession`, `websession`, `ids`, `gw_net_stats`, `gw_sys_stats`, `cmd`,
`tunnel_status`, `vpn_session`). Build the CLI column list from it rather than
typing a partial one:

```bash
SCHEMA=deployments/azure-aci/module/ai/4-table-schemas.tf   # run from the repo root
cols() { sed -n "/^    $1 = \[/,/^    \]/p" "$SCHEMA" | sed -nE 's/.*name = "([^"]+)", type = "([^"]+)".*/\1=\2/p' | tr '\n' ' '; }

az monitor log-analytics workspace table create \
    --resource-group <rg> --workspace-name <workspace> \
    --name "AviatrixNetworkSession_CL" --columns $(cols netsession)
# Repeat for AviatrixWebSession_CL (websession), AviatrixIDS_CL (ids),
# AviatrixGwNetStats_CL (gw_net_stats), AviatrixGwSysStats_CL (gw_sys_stats),
# AviatrixCmd_CL (cmd), AviatrixTunnelStatus_CL (tunnel_status),
# AviatrixVPNSession_CL (vpn_session)
```

### 3. Create Data Collection Endpoint (DCE)

```bash
az monitor data-collection endpoint create \
    --resource-group <rg> \
    --name "aviatrix-dce" \
    --public-network-access Enabled
```

### 4. Create Data Collection Rules (DCR)

Create one DCR per log type (8 in total) on the DCE above, each with:

- a stream declaration `Custom-<Table>` whose columns are exactly the table's columns
  (same list as step 2; as JSON: `sed -n "/^    netsession = \[/,/^    \]/p" "$SCHEMA" | sed -nE 's/.*name = "([^"]+)", type = "([^"]+)".*/{"name":"\1","type":"\2"}/p' | paste -sd, - | sed 's/^/[/; s/$/]/'`)
- a data flow from that stream to the Log Analytics workspace with `transformKql: "source"`
  and `outputStream: Custom-<Table>`

The Terraform definitions in `deployments/azure-aci/module/ai/2-data-collection.tf`
are the reference implementation.

### 5. Create Service Principal

```bash
az ad sp create-for-rbac --name "aviatrix-logstash" --role "Monitoring Metrics Publisher" \
    --scopes /subscriptions/<subscription-id>/resourceGroups/<rg>
```

Grant the service principal access to the DCRs.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `client_app_id` | Yes | — | Azure AD application (service principal) ID |
| `client_app_secret` | Yes | — | Azure AD application secret |
| `tenant_id` | Yes | — | Azure AD tenant ID |
| `data_collection_endpoint` | Yes | — | Data Collection Endpoint URL |
| `azure_cloud` | No | `AzureCloud` | `AzureCloud`, `AzureChinaCloud`, or `AzureUSGovernment` |
| `LOG_PROFILE` | No | `all` | Log type filter: `all`, `security`, or `networking` |
| `azure_dcr_netsession_id` | Yes* | — | DCR immutable ID for L4 Network Session (ASIM) |
| `azure_stream_netsession` | Yes* | — | Stream name (e.g., `Custom-AviatrixNetworkSession_CL`) |
| `azure_dcr_websession_id` | Yes* | — | DCR immutable ID for L7 Web Session (ASIM) |
| `azure_stream_websession` | Yes* | — | Stream name (e.g., `Custom-AviatrixWebSession_CL`) |
| `azure_dcr_ids_id` | Yes* | — | DCR immutable ID for IDS/Suricata (ASIM) |
| `azure_stream_ids` | Yes* | — | Stream name (e.g., `Custom-AviatrixIDS_CL`) |
| `azure_dcr_gw_net_stats_id` | Yes* | — | DCR immutable ID for Gateway Network Stats |
| `azure_stream_gw_net_stats` | Yes* | — | Stream name (e.g., `Custom-AviatrixGwNetStats_CL`) |
| `azure_dcr_gw_sys_stats_id` | Yes* | — | DCR immutable ID for Gateway System Stats |
| `azure_stream_gw_sys_stats` | Yes* | — | Stream name (e.g., `Custom-AviatrixGwSysStats_CL`) |
| `azure_dcr_cmd_id` | Yes* | — | DCR immutable ID for Controller CMD/API |
| `azure_stream_cmd` | Yes* | — | Stream name (e.g., `Custom-AviatrixCmd_CL`) |
| `azure_dcr_tunnel_status_id` | Yes* | — | DCR immutable ID for Tunnel Status |
| `azure_stream_tunnel_status` | Yes* | — | Stream name (e.g., `Custom-AviatrixTunnelStatus_CL`) |
| `azure_dcr_vpn_session_id` | Yes* | — | DCR immutable ID for VPN Session |
| `azure_stream_vpn_session` | Yes* | — | Stream name (e.g., `Custom-AviatrixVPNSession_CL`) |

\* All 8 DCR/stream pairs are required **regardless of `LOG_PROFILE`**: Logstash
resolves every `${VAR}` when it compiles the pipeline, so an unset variable stops
the pipeline from loading even if that log type is never forwarded.

## Quick Start

### 1. Build the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh azure-log-ingestion
```

This creates `assembled/azure-log-ingestion-full.conf`.

### 2. Run Logstash

```bash
docker run -d --restart=always \
  --name logstash-aviatrix \
  -v /path/to/assembled/azure-log-ingestion-full.conf:/usr/share/logstash/pipeline/logstash.conf \
  -v /path/to/patterns:/usr/share/logstash/patterns \
  -e client_app_id=your-app-id \
  -e client_app_secret=your-app-secret \
  -e tenant_id=your-tenant-id \
  -e data_collection_endpoint=https://your-dce.ingest.monitor.azure.com \
  -e azure_dcr_netsession_id=dcr-xxxxx \
  -e azure_stream_netsession=Custom-AviatrixNetworkSession_CL \
  -e azure_dcr_websession_id=dcr-yyyyy \
  -e azure_stream_websession=Custom-AviatrixWebSession_CL \
  -e azure_dcr_ids_id=dcr-zzzzz \
  -e azure_stream_ids=Custom-AviatrixIDS_CL \
  -e azure_dcr_gw_net_stats_id=dcr-aaaaa \
  -e azure_stream_gw_net_stats=Custom-AviatrixGwNetStats_CL \
  -e azure_dcr_gw_sys_stats_id=dcr-bbbbb \
  -e azure_stream_gw_sys_stats=Custom-AviatrixGwSysStats_CL \
  -e azure_dcr_cmd_id=dcr-ccccc \
  -e azure_stream_cmd=Custom-AviatrixCmd_CL \
  -e azure_dcr_tunnel_status_id=dcr-ddddd \
  -e azure_stream_tunnel_status=Custom-AviatrixTunnelStatus_CL \
  -e azure_dcr_vpn_session_id=dcr-eeeee \
  -e azure_stream_vpn_session=Custom-AviatrixVPNSession_CL \
  -e azure_cloud=AzureCloud \
  -e LOG_PROFILE=all \
  -e XPACK_MONITORING_ENABLED=false \
  -p 5000:5000/tcp \
  -p 5000:5000/udp \
  your-registry.azurecr.io/aviatrix-logstash-sentinel:latest
```

## Supported Log Types

| Log Type | Azure Table | ASIM Schema |
|---|---|---|
| L4 Microsegmentation | `AviatrixNetworkSession_CL` | NetworkSession |
| L7 MITM/TLS Inspection | `AviatrixWebSession_CL` | WebSession |
| Suricata IDS | `AviatrixIDS_CL` | NetworkSession (IDS) |
| Gateway Network Stats | `AviatrixGwNetStats_CL` | (none) |
| Gateway System Stats | `AviatrixGwSysStats_CL` | (none) |
| Controller CMD/API | `AviatrixCmd_CL` | (none) |
| Tunnel Status | `AviatrixTunnelStatus_CL` | (none) |
| VPN Session | `AviatrixVPNSession_CL` | (none) |

FQDN firewall events are parsed but have no Azure output.

## ASIM Parsers

KQL parser files for Sentinel ASIM integration are in `asim-parsers/`:
- `vimNetworkSessionAviatrixGateway.kql` - L4 microseg
- `vimWebSessionAviatrixGateway.kql` - L7 MITM
- `vimNetworkSessionAviatrixSuricata.kql` - Suricata IDS

See deployment instructions in each `.kql` file. Saving the functions does not
by itself add Aviatrix rows to `_Im_NetworkSession` / `_Im_WebSession`; see
"ASIM integration" in [deployments/azure-aci/README.md](../../../deployments/azure-aci/README.md#asim-parser-deployment-optional).

## Sample Output Files

The `_sample*.json` files show one row per security table as it lands in Log
Analytics (fields limited to declared columns), generated from the current
`output.conf` ASIM mapping using events from `test-tools/sample-logs/test-samples.log`:
- `_sampleMicrosegOutput.json` - `AviatrixNetworkSession_CL` (L4 microseg session end)
- `_sampleWebSessionOutput.json` - `AviatrixWebSession_CL` (L7 MITM TLS-check event)
- `_sampleSuricataOutput.json` - `AviatrixIDS_CL` (Suricata alert)

## Terraform Deployment

For Azure ACI deployment, see [deployments/azure-aci/README.md](../../../deployments/azure-aci/README.md).

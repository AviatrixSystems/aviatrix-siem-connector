# Azure Log Analytics Output

This output configuration sends parsed Aviatrix logs to Azure Log Analytics via the Data Collection Rules (DCR) API using the Microsoft Sentinel Logstash plugin.

## Quick Start

### 1. Build the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh azure-log-ingestion
```

This creates `assembled/azure-log-ingestion-full.conf`.

### 2. Configure Environment Variables

| Variable | Description |
|----------|-------------|
| `client_app_id` | Azure AD application (service principal) ID |
| `client_app_secret` | Azure AD application secret |
| `tenant_id` | Azure AD tenant ID |
| `data_collection_endpoint` | Data Collection Endpoint URL |
| `azure_dcr_suricata_id` | DCR immutable ID for Suricata logs |
| `azure_stream_suricata` | Stream name for Suricata (e.g., `Custom-AviatrixSuricata_CL`) |
| `azure_dcr_microseg_id` | DCR immutable ID for Microseg logs |
| `azure_stream_microseg` | Stream name for Microseg (e.g., `Custom-AviatrixMicroseg_CL`) |
| `azure_cloud` | `public` or `china` |

### 3. Run Logstash

```bash
docker run -d --restart=always \
  --name logstash-aviatrix \
  -v /path/to/assembled/azure-log-ingestion-full.conf:/usr/share/logstash/pipeline/logstash.conf \
  -v /path/to/patterns:/usr/share/logstash/patterns \
  -e client_app_id=your-app-id \
  -e client_app_secret=your-app-secret \
  -e tenant_id=your-tenant-id \
  -e data_collection_endpoint=https://your-dce.ingest.monitor.azure.com \
  -e azure_dcr_suricata_id=dcr-xxxxx \
  -e azure_stream_suricata=Custom-AviatrixSuricata_CL \
  -e azure_dcr_microseg_id=dcr-yyyyy \
  -e azure_stream_microseg=Custom-AviatrixMicroseg_CL \
  -e azure_cloud=public \
  -e XPACK_MONITORING_ENABLED=false \
  -p 5000:5000/tcp \
  -p 5000:5000/udp \
  docker.elastic.co/logstash/logstash:8.16.2
```

## Prerequisites

### 1. Create Custom Log Analytics Tables

```bash
# Microseg table
az monitor log-analytics workspace table create \
    --resource-group <rg> \
    --workspace-name <workspace> \
    --name "AviatrixMicroseg_CL" \
    --columns \
        TimeGenerated=datetime \
        action=string \
        src_ip=string \
        dst_ip=string \
        src_port=int \
        dst_port=int \
        proto=string \
        uuid=string \
        enforced=boolean \
        gw_hostname=string

# Suricata table
az monitor log-analytics workspace table create \
    --resource-group <rg> \
    --workspace-name <workspace> \
    --name "AviatrixSuricata_CL" \
    --columns \
        TimeGenerated=datetime \
        src_ip=string \
        dest_ip=string \
        src_port=int \
        dest_port=int \
        proto=string \
        alert=dynamic \
        event_type=string \
        gw_hostname=string
```

### 2. Create Data Collection Endpoint (DCE)

```bash
az monitor data-collection endpoint create \
    --resource-group <rg> \
    --name "aviatrix-dce" \
    --public-network-access Enabled
```

### 3. Create Data Collection Rules (DCR)

Create DCRs for each log type. See `output_loganalytics_sentinel_dcr/avx_dcf_dcr.json` for a template.

### 4. Create Service Principal

```bash
az ad sp create-for-rbac --name "aviatrix-logstash" --role "Monitoring Metrics Publisher" \
    --scopes /subscriptions/<subscription-id>/resourceGroups/<rg>
```

Grant the service principal access to the DCRs.

## Supported Log Types

Currently, this output supports:
- **Suricata IDS** - Sent to `AviatrixSuricata_CL`
- **L4 Microsegmentation** - Sent to `AviatrixMicroseg_CL`

## Sample Output Files

The `_sample*.json` files in this directory show example output formats:
- `_sampleMicrosegOutput.json` - Microseg event structure
- `_sampleSuricataOutput.json` - Suricata event structure

## Terraform Deployment

For Azure ACI deployment, see [deployment-tf/azure-aci/README.md](../../../deployment-tf/azure-aci/README.md).

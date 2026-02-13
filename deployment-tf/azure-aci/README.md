# Azure Container Instances (ACI) Logstash Deployment

This Terraform configuration deploys a Logstash container on Azure Container Instances (ACI) with the below specifications.
It uses the Microsoft Log Ingestion API along with the Microsoft Sentinel Logstash output plugin.
> For detailed guidance on connecting Logstash to Microsoft Sentinel using Data Collection Rules, see the [Microsoft Learn article](https://learn.microsoft.com/en-us/azure/sentinel/connect-logstash-data-connection-rules).

## Architecture Diagram

![Log Engine API Architecture](images/log-engine-api.png)

## Configuration Details

- **Location**: Provide any preferred Azure region
- **Container Image**: aviatrixacr.azurecr.io/aviatrix-logstash-sentinel
  - This is a custom image built with the Azure Log Ingestion API plugin. You can built your own following [README](logstash-container-build/README.md) into the logstash-container-builder folder. Update your terraform.tfvars file accordingly.
- **Resources**: 1 vCPU, 1.5GB memory
  - You can adapt to the expected load on your container.
- **Network**: Public IP with TCP port 5000 exposed.
  - You can use UDP for higher performance by updating "container_protocol" variable.
- **OS Type**: Linux
- **Storage**: Azure File Shares mounted at `/usr/share/logstash/pipeline` and `/usr/share/logstash/patterns` for configuration and pattern files
- **Logging**: Provide your own Lag Analytcis workspace's name and resource group using log_analytics_workspace_name and log_analytics_resource_group_name variables.

## Prerequisites
1. Azure CLI installed  
2. Azure CLI authenticated

   - ```az cloud set --name AzureCloud``` to point az cli to public cloud
   - ```az cloud set --name AzureChinaCloud``` to point az cli to China cloud
3. Terraform >= 1.0 installed  
4. Existing Log Analytics workspace and resource group information. If your Log Analyics workspace lives in a different subscription, provide the subscription ID using the log_analytics_subscription_id parameter.
5. Custom container containing Logstash and the Sentinel plugin (actual source here is supplied as **best effort**). You should build/use your own source. See the [README](./logstash-container-build/README.md) for instructions.  
6. Log Analytics Custom Log tables for Microseg and Suricata logs. Use the two command lines provided below to create tables.  
7. EntraID Service Principal: you can decide to use a pre-created Service Principal (default) or let the Terraform deployment create one for you.  
   - By default, `use_existing_spn` is set to `true` so you have to provide values of an existing Service Principal ID (`client_app_id`), secret (`client_app_secret`), and tenant ID (`tenant_id`) in the `terraform.tfvars` file.  
   - For the Terraform deployment to create the Service Principal automatically, override the `use_existing_spn` variable with value `false`. **You must have the "Application Administrator" or "Cloud Application Administrator" role in Azure Entra ID. These roles allow you to create and manage applications required and used by the Logstash plugin to push logs to Log Analytics.**

## Azure public or Azure China deployment

You can deploy that log engine into a region part of Azure Public cloud or inside one of the Azure China regions by running terraform from the appropriate folder.

| Cloud | Folder |
|----------|-------------|
| Public | `deploy-public` |
| China | `deploy-china` |

## Deployment Steps

This is a first release that mixes Terraform code along with some Azure CLI commands as not everything was available in Terraform.

### Custom log table creation example (not available through Terraform azurerm provider yet)

#### AviatrixMicroseg_CL - L4 Microsegmentation and L7 MITM/TLS Inspection

This table stores both L4 microsegmentation logs and L7 MITM/TLS inspection logs.

```bash
az monitor log-analytics workspace table create \
    --resource-group <your-resource-group-name> \
    --workspace-name <your-log-analytics-workspace-name> \
    --name "AviatrixMicroseg_CL" \
    --columns \
        TimeGenerated=datetime \
        Computer=string \
        RawData=string \
        action=string \
        proto=string \
        src_ip=string \
        src_port=string \
        dst_ip=string \
        dst_port=string \
        enforced=string \
        uuid=string \
        gw_ip=string \
        src_mac=string \
        dst_mac=string \
        ip_size=string \
        session_id=string \
        session_event=string \
        session_end_reason=string \
        session_pkt_cnt=string \
        session_byte_cnt=string \
        session_dur=string \
        direction=string \
        mitm_sni_hostname=string \
        mitm_url_parts=string \
        mitm_decrypted_by=string \
        gw_hostname=string \
        message=string \
        unix_time=long
```

**Field Descriptions:**

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `TimeGenerated` | datetime | All | Event timestamp (required by Azure) |
| `action` | string | L4, MITM | PERMIT or DENY |
| `proto` | string | L4, MITM | Protocol (TCP, UDP, ICMP) |
| `src_ip`, `src_port` | string | L4, MITM | Source IP and port |
| `dst_ip`, `dst_port` | string | L4, MITM | Destination IP and port |
| `enforced` | string | L4, MITM | Enforcement status (true/false) |
| `uuid` | string | L4, MITM | Rule UUID |
| `session_*` | string | L4 | Session fields (8.2+): id, event, end_reason, pkt_cnt, byte_cnt, dur |
| `mitm_sni_hostname` | string | MITM | SNI hostname from TLS handshake (e.g., "github.com") |
| `mitm_url_parts` | string | MITM | Full URL if available |
| `mitm_decrypted_by` | string | MITM | Gateway that decrypted the traffic |

#### AviatrixSuricata_CL - IDS/IPS Alerts

```bash
az monitor log-analytics workspace table create \
   --resource-group <your-resource-group-name> \
   --workspace-name <your-log-analytics-workspace-name> \
   --name "AviatrixSuricata_CL" \
   --columns \
        TimeGenerated=datetime \
        Computer=string \
        RawData=string \
        timestamp=string \
        flow_id=long \
        event_type=string \
        src_ip=string \
        src_port=int \
        dest_ip=string \
        dest_port=int \
        proto=string \
        alert_action=string \
        alert_signature=string \
        alert_category=string \
        alert_severity=int \
        alert_signature_id=int \
        alert_rev=int \
        alert_gid=int \
        gw_hostname=string \
        message=string \
        unix_time=long
```

| Log Type | Stream Name | Custom Table | Description |
|----------|-------------|--------------|-------------|
| Suricata | `Custom-AviatrixSuricata_CL` | `AviatrixSuricata_CL` | Intrusion Detection System logs |
| Microseg (L4) | `Custom-AviatrixMicroseg_CL` | `AviatrixMicroseg_CL` | Layer 4 microsegmentation logs |
| MITM (L7) | `Custom-AviatrixMicroseg_CL` | `AviatrixMicroseg_CL` | Layer 7 TLS inspection logs with SNI hostname |

#### Updating Existing Tables

If you need to add fields to an existing table (e.g., adding MITM fields):

```bash
az monitor log-analytics workspace table update \
    --resource-group <your-resource-group-name> \
    --workspace-name <your-log-analytics-workspace-name> \
    --name "AviatrixMicroseg_CL" \
    --columns <full-column-list-including-new-fields>
```

**Note:** You must provide the complete column list when updating. See [AZURE_LOG_ANALYTICS_SETUP.md](../../AZURE_LOG_ANALYTICS_SETUP.md) for detailed schema documentation.

Below is a screenshot showing the custom tables created in Log Analytics:

![Custom Tables Example](images/loganalytics-custom-tables.png)

### Terraform deployment part

Duplicate the `terraform.tfvars.sample` to `terraform.tfvars` and provide values for each variable. If you rename the file with a different name, you will have to use the -var-file switch with the new name otherwise, do not use the switch : Terraform will pickup you variable file automatically.

Once deployed, come back here to continue with SPN IAM role assignment

1. **Go to folder containing TF config**:

   ```bash
   cd .\deployment-tf\azure-aci\deploy-public,china
   ```

2. **Validate Prerequisites**:
   ```bash
   ../scripts/validate-deployment.sh
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Review the plan**:
   ```bash
   terraform plan [-var-file="terraform.tfvars"]
   ```

5. **Apply the configuration**:
   ```bash
   terraform apply [-var-file="terraform.tfvars"]
   ```

6. **Get outputs**:
   ```bash
   terraform output
   ```

## Aviatrix Log export configuration

Configure Aviatrix Copilot to export logs to the newly deployed Azure Container Instance containing Logstash. Use the outputs of the previous terraform deployment.

### Aviatrix Copilot Log Export Configuration

To export logs from Aviatrix Copilot to the Azure Container Instance running Logstash, follow these steps:

1. **Access Copilot UI**: Log in to your Aviatrix Copilot dashboard.
2. **Navigate to Log Export Settings**: Go to *Settings* > *Configuration* > *Logging services* > *Edit Profile* under Remote Syslog.
3. **Configure Syslog Export**:
   - **Profile**: Select a profile from 1 to 8 (not removing Copilot's profile)
   - **Profile Name**: Give it a name
   - **Server**: Use the `container_group_fqdn` output from Terraform.
   - **Port**: Set to `5000` (or your configured port).
   - **Protocol**: Select `TCP` (or `UDP` if configured).
4. **Save**: Save the configuration.

[See the Aviatrix Copilot documentation for more detailed instructions on configuring Syslog profiles.](https://docs.aviatrix.com/documentation/latest/platform-administration/copilot/aviatrix-logging-copilot.html#syslog-profiles)

Logs from Copilot will now be forwarded to Logstash in the Azure Container Instance for processing. Upon messages recognition, logs will be sent to Azure Log Analytics via the Azure Log Ingestion API.

## Clean Up

To destroy the resources:
```bash
terraform destroy
```

You also have to delete the two custom tables that were created manually using Azure CLI.

## Log Analytics output examples

Below are sample screenshots of Log Analytics queries and dashboards using data ingested from Logstash:

### Microseg Log Table Example

![Microseg Log Table](images/loganalytics-microseg-example.png)

### Suricata Log Table Example

![Suricata Log Table](images/loganalytics-suricata-example.png)

## Troubleshooting

### Accessing Logstash

After deployment, Logstash will be accessible at:
- **FQDN**: The output `container_group_fqdn` will provide the full domain name. That is what needs to be used to configure an additional  Copilot remote logging profil in addition to the one for Copilot. (Steps given below.)

You can also attach to container to read ouput easily:
```bash
# Attach to the running Logstash container in ACI
az container attach \
   --resource-group <your-resource-group> \
   --name <your-container-group-name>
```
Replace `<your-resource-group>` and `<your-container-group-name>` with your actual resource group and container group names.

### Logstash Configuration

The deployment automatically uploads the following configuration files to the Azure File Share:

- **Main Configuration**: `pipeline/logstash.conf` (from `../../logstash-configs/assembled/azure-log-ingestion-full.conf`)
- **Patterns**: `patterns/avx.conf` (from `../../logstash-configs/patterns/avx.conf`)

These files are mounted to the container at `/usr/share/logstash/pipeline` and `/usr/share/logstash/patterns` respectively.

**IMPORTANT:** Before deploying, ensure you have assembled the config:
```bash
cd logstash-configs
./scripts/assemble-config.sh azure-log-ingestion
```

If you decide to change any filter or pattern, reassemble the config and re-apply Terraform to update the Azure File Share. The container is configured for auto reload using `CONFIG_RELOAD_AUTOMATIC=true`.
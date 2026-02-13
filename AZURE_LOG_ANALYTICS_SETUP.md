
---

## Troubleshooting: Missing Fields in Azure Queries

### Problem: Fields like SNI hostname not appearing in Azure Log Analytics

If you're sending logs with fields like `mitm_sni_hostname` but they're not appearing when you query Azure Log Analytics, the issue is that **the table schema doesn't include those columns**.

Azure Log Analytics custom tables require explicit schema definition. Any fields not in the schema are silently dropped during ingestion.

### Solution: Update Table Schema

Use the `az monitor log-analytics workspace table update` command to add the missing fields. You must provide the **complete** column list including all existing and new fields.

**Example: Adding MITM fields to existing AviatrixMicroseg_CL table:**

```bash
az monitor log-analytics workspace table update \
    --resource-group "aviatrix-siem-connector" \
    --workspace-name "aviatrix-siem-workspace" \
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

### Finding Your Workspace Details

If you're not sure which workspace or resource group to use:

```bash
# Find workspace by customerId (from queries)
az monitor log-analytics workspace list \
    --query "[?customerId=='<your-workspace-id>'].{name:name, resourceGroup:resourceGroup}" \
    --output table
```

### Verification

After updating the schema, query for the new fields (remember Azure appends type suffixes):

```bash
az monitor log-analytics query \
    --workspace "<workspace-id>" \
    --analytics-query "AviatrixMicroseg_CL | where TimeGenerated > ago(1h) and isnotempty(mitm_sni_hostname_s) | project TimeGenerated, mitm_sni_hostname_s" \
    --output table
```

**Note:** Schema changes may take a few minutes to propagate. New logs sent after the schema update will include the new fields.

---

## Schema Update History

### 2026-02-03: Added MITM/L7 DCF Fields

Added three fields to support L7 TLS inspection logs:
- `mitm_sni_hostname` - SNI hostname from TLS handshake
- `mitm_url_parts` - Full URL if available  
- `mitm_decrypted_by` - Gateway that decrypted the traffic

**Workspace:** aviatrix-siem-workspace  
**Resource Group:** aviatrix-siem-connector  
**Command:** See complete schema above

### Updating the Data Collection Rule (DCR)

**IMPORTANT:** After updating the table schema, you **must also update the DCR** to include the new fields in its stream declaration. The DCR acts as a filter - even if the table has the columns, the DCR won't pass fields through that aren't in its stream definition.

**Steps to update the DCR:**

1. Get the current DCR configuration:
```bash
az monitor data-collection rule show \
    --resource-group "aviatrix-siem-connector" \
    --name "aviatrix-microseg-dcr" \
    --output json > dcr-config.json
```

2. Update the stream declaration to include all fields (matching the table schema).  You can use `jq` to programmatically update it, or manually edit the JSON file.

3. Update the DCR using Azure REST API:
```bash
# Create the API payload with proper structure
cat dcr-config.json | jq '{
  location: .location,
  kind: .kind,
  properties: {
    dataCollectionEndpointId: .dataCollectionEndpointId,
    streamDeclarations: .streamDeclarations,
    dataSources: .dataSources,
    destinations: .destinations,
    dataFlows: .dataFlows
  }
}' > dcr-api-payload.json

# Apply the update
az rest --method PUT \
    --uri "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Insights/dataCollectionRules/<dcr-name>?api-version=2022-06-01" \
    --body @dcr-api-payload.json
```

**Example: Adding MITM fields to the DCR stream declaration:**

The stream declaration in the DCR should match the table schema. For `Custom-AviatrixMicroseg_CL`, it should include all 26 columns including the MITM fields:

```json
{
  "Custom-AviatrixMicroseg_CL": {
    "columns": [
      {"name": "TimeGenerated", "type": "datetime"},
      {"name": "action", "type": "string"},
      ...
      {"name": "mitm_sni_hostname", "type": "string"},
      {"name": "mitm_url_parts", "type": "string"},
      {"name": "mitm_decrypted_by", "type": "string"},
      ...
    ]
  }
}
```

**Verification:**

After updating the DCR, send test logs and verify the new fields appear:

```bash
# Check stream declaration was updated
az monitor data-collection rule show \
    --resource-group "aviatrix-siem-connector" \
    --name "aviatrix-microseg-dcr" \
    --query "properties.streamDeclarations.\"Custom-AviatrixMicroseg_CL\".columns | length(@)"

# Should show 26 (or your total column count)
```

Send new test logs after the DCR update, and the MITM fields should now appear in Azure Log Analytics queries.

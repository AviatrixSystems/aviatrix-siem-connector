# Azure Log Analytics: Troubleshooting Missing Fields

Setup and deployment are covered in
[deployments/azure-aci/README.md](../deployments/azure-aci/README.md) (Terraform) and
[logstash-configs/outputs/azure-log-ingestion/README.md](../logstash-configs/outputs/azure-log-ingestion/README.md)
(output config, manual setup). This page only covers one recurring problem: a field
that Logstash sends never shows up in Log Analytics.

> This page previously described a pre-ASIM `AviatrixMicroseg_CL` table and an
> `aviatrix-microseg-dcr` DCR. Neither exists in current deployments; do not run
> commands against those names.

## Why fields go missing

The pipeline sends events through the Logs Ingestion API to one Data Collection
Rule (DCR) per log type. Each DCR has a stream declaration (`Custom-<Table>`) and a
pass-through transform (`transformKql: "source"`). Ingestion keeps only the
properties that are declared in **both**:

1. the DCR stream declaration, and
2. the destination table schema.

Anything else is dropped silently, with no error in Logstash or Azure.

| Log type | Table | DCR (Terraform) | Schema key |
|---|---|---|---|
| L4 microseg | `AviatrixNetworkSession_CL` | `aviatrix-netsession-dcr` | `netsession` |
| L7 MITM/DCF | `AviatrixWebSession_CL` | `aviatrix-websession-dcr` | `websession` |
| Suricata IDS | `AviatrixIDS_CL` | `aviatrix-ids-dcr` | `ids` |
| Gateway net stats | `AviatrixGwNetStats_CL` | `aviatrix-gw-net-stats-dcr` | `gw_net_stats` |
| Gateway sys stats | `AviatrixGwSysStats_CL` | `aviatrix-gw-sys-stats-dcr` | `gw_sys_stats` |
| Controller CMD/API | `AviatrixCmd_CL` | `aviatrix-cmd-dcr` | `cmd` |
| Tunnel status | `AviatrixTunnelStatus_CL` | `aviatrix-tunnel-status-dcr` | `tunnel_status` |
| VPN session | `AviatrixVPNSession_CL` | `aviatrix-vpn-session-dcr` | `vpn_session` |

## Fix (Terraform deployments)

Both the table columns and the DCR stream columns are generated from a single list
per table in
[`deployments/azure-aci/module/ai/4-table-schemas.tf`](../deployments/azure-aci/module/ai/4-table-schemas.tf).

1. Add the column to the right list (append at the end), e.g.
   `{ name = "my_new_field", type = "string" },`
   Types: `string`, `int`, `long`, `real`, `boolean`, `datetime`, `dynamic`.
2. `terraform apply` from `deployments/azure-aci/deploy-public` (or `deploy-china`).
   This updates the table and the DCR in place.
3. Send new events. Rows ingested before the change are not backfilled.

Do not hand-edit the table or DCR in the portal or CLI for a Terraform-managed
deployment; the next apply reverts it.

## Fix (manual deployments)

Add the column to the table **and** to the DCR stream declaration, keeping both
identical to the list in `4-table-schemas.tf`:

```bash
# Table: pass the complete column list (the helper is in the output README)
az monitor log-analytics workspace table update \
    --resource-group <rg> --workspace-name <workspace> \
    --name "AviatrixWebSession_CL" --columns $(cols websession)

# DCR: export, edit the stream declaration columns, and PUT it back
az monitor data-collection rule show --resource-group <rg> --name <dcr-name> -o json > dcr.json
# edit dcr.json: add the column under
#   streamDeclarations."Custom-AviatrixWebSession_CL".columns
# (depending on your az CLI version the key is at the top level or under .properties)
```

## Verify

Column names are stored exactly as declared. DCR-based custom tables do **not** add
type suffixes such as `_s` or `_d` (those apply only to the legacy HTTP Data
Collector API), so query the bare name:

```kql
AviatrixWebSession_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, DvcHostname, DstFqdn, NetworkSessionId, ThreatId, EventSubType
| take 10
```

Check what a DCR currently declares:

```bash
az monitor data-collection rule show --resource-group <rg> --name aviatrix-websession-dcr \
    --query "streamDeclarations.\"Custom-AviatrixWebSession_CL\".columns[].name" -o tsv
```

If that returns nothing, retry the query with the `properties.` prefix
(`properties.streamDeclarations...`); the output shape differs between az CLI versions.

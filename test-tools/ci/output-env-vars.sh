#!/bin/bash
# output-env-vars.sh - Print dummy env vars for Logstash config validation
# Usage: ./output-env-vars.sh <output-type> [assembled-config]
#   Prints one "-e NAME=value" line per variable (docker run flags). Strip the
#   leading "-e " to get a --env-file.
#
# Known output types get realistic dummy values below. In addition, every
# ${VAR} reference without a default in the assembled config (default:
# logstash-configs/assembled/<type>-full.conf) that is not set here gets a
# "dummy" stub, so a new variable in an output.conf cannot break the CI
# config test, and a new output type works without editing this file.
set -euo pipefail

OUTPUT_TYPE="${1:?Usage: output-env-vars.sh <output-type> [assembled-config]}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${2:-$SCRIPT_DIR/../../logstash-configs/assembled/${OUTPUT_TYPE}-full.conf}"

emit_known() {
# Common env vars
echo "-e XPACK_MONITORING_ENABLED=false"
echo "-e LOG_PROFILE=all"
echo "-e SYSLOG_PORT=5000"

case "$OUTPUT_TYPE" in
    splunk-hec)
        echo "-e SPLUNK_ADDRESS=dummy.example.com"
        echo "-e SPLUNK_PORT=8088"
        echo "-e SPLUNK_HEC_AUTH=dummy-token"
        ;;
    dynatrace)
        echo "-e DT_METRICS_URL=https://dummy.dynatrace.com/api/v2/metrics/ingest"
        echo "-e DT_LOGS_URL=https://dummy.dynatrace.com/api/v2/logs/ingest"
        echo "-e DT_API_TOKEN=dummy-token"
        echo "-e DT_LOGS_TOKEN=dummy-token"
        ;;
    dynatrace-metrics)
        echo "-e DT_METRICS_URL=https://dummy.dynatrace.com/api/v2/metrics/ingest"
        echo "-e DT_API_TOKEN=dummy-token"
        ;;
    dynatrace-logs)
        echo "-e DT_LOGS_URL=https://dummy.dynatrace.com/api/v2/logs/ingest"
        echo "-e DT_LOGS_TOKEN=dummy-token"
        ;;
    webhook-test)
        echo "-e WEBHOOK_URL=http://dummy.example.com/webhook"
        ;;
    ci-test)
        # No additional env vars needed
        ;;
    zabbix)
        echo "-e ZABBIX_SERVER=dummy.example.com"
        echo "-e ZABBIX_PORT=10051"
        ;;
    azure-log-ingestion)
        echo "-e client_app_id=dummy-client-id"
        echo "-e client_app_secret=dummy-client-secret"
        echo "-e tenant_id=dummy-tenant-id"
        echo "-e data_collection_endpoint=https://dummy.ingest.monitor.azure.com"
        echo "-e azure_dcr_netsession_id=dcr-dummy1"
        echo "-e azure_dcr_websession_id=dcr-dummy2"
        echo "-e azure_dcr_ids_id=dcr-dummy3"
        echo "-e azure_dcr_gw_net_stats_id=dcr-dummy4"
        echo "-e azure_dcr_gw_sys_stats_id=dcr-dummy5"
        echo "-e azure_dcr_cmd_id=dcr-dummy6"
        echo "-e azure_dcr_tunnel_status_id=dcr-dummy7"
        echo "-e azure_dcr_vpn_session_id=dcr-dummy8"
        echo "-e azure_stream_netsession=Custom-AviatrixNetworkSession_CL"
        echo "-e azure_stream_websession=Custom-AviatrixWebSession_CL"
        echo "-e azure_stream_ids=Custom-AviatrixIDS_CL"
        echo "-e azure_stream_gw_net_stats=Custom-AviatrixGwNetStats_CL"
        echo "-e azure_stream_gw_sys_stats=Custom-AviatrixGwSysStats_CL"
        echo "-e azure_stream_cmd=Custom-AviatrixCmd_CL"
        echo "-e azure_stream_tunnel_status=Custom-AviatrixTunnelStatus_CL"
        echo "-e azure_stream_vpn_session=Custom-AviatrixVPNSession_CL"
        echo "-e azure_cloud=AzureCloud"
        ;;
    *)
        # Unknown type: rely on the generated stubs below.
        ;;
esac
}

KNOWN="$(emit_known)"
echo "$KNOWN"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: assembled config not found: $CONFIG_FILE" >&2
    echo "Run logstash-configs/scripts/assemble-config.sh $OUTPUT_TYPE first." >&2
    exit 1
fi

# ${NAME} without a ":default" must be set, or Logstash refuses the config.
grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$CONFIG_FILE" | sort -u | while read -r ref; do
    name="${ref#\$\{}"
    name="${name%\}}"
    if ! grep -q -- "^-e ${name}=" <<< "$KNOWN"; then
        echo "-e ${name}=dummy"
    fi
done

#!/bin/bash
# output-env-vars.sh - Print dummy env vars for Logstash config validation
# Usage: source <(./output-env-vars.sh <output-type>)
#   or:  ./output-env-vars.sh <output-type>  (prints -e flags for docker run)
set -euo pipefail

OUTPUT_TYPE="${1:?Usage: output-env-vars.sh <output-type>}"

# Common env vars
echo "-e XPACK_MONITORING_ENABLED=false"
echo "-e LOG_PROFILE=all"

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
        echo "-e azure_stream_netsession=Custom-AviatrixNetworkSession_CL"
        echo "-e azure_stream_websession=Custom-AviatrixWebSession_CL"
        echo "-e azure_stream_ids=Custom-AviatrixIDS_CL"
        echo "-e azure_stream_gw_net_stats=Custom-AviatrixGwNetStats_CL"
        echo "-e azure_stream_gw_sys_stats=Custom-AviatrixGwSysStats_CL"
        echo "-e azure_stream_cmd=Custom-AviatrixCmd_CL"
        echo "-e azure_stream_tunnel_status=Custom-AviatrixTunnelStatus_CL"
        echo "-e azure_cloud=AzureCloud"
        ;;
    *)
        echo "Error: Unknown output type '$OUTPUT_TYPE'" >&2
        echo "Supported types: splunk-hec, dynatrace, dynatrace-metrics, dynatrace-logs, webhook-test, ci-test, zabbix, azure-log-ingestion" >&2
        exit 1
        ;;
esac

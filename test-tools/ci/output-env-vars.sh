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
    *)
        echo "Error: Unknown output type '$OUTPUT_TYPE'" >&2
        echo "Supported types: splunk-hec, dynatrace, dynatrace-metrics, dynatrace-logs, webhook-test, ci-test" >&2
        exit 1
        ;;
esac

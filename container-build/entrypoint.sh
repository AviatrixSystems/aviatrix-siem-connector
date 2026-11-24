#!/bin/bash
# GHCR image entrypoint: pick the baked config for OUTPUT_TYPE, then hand off to
# the stock Logstash entrypoint so env2yaml still maps env vars such as
# PIPELINE_WORKERS, PIPELINE_BATCH_SIZE, LOG_LEVEL and CONFIG_RELOAD_AUTOMATIC
# into logstash.yml.
#
# Container args are passed to Logstash, e.g.
#   docker run --rm -e OUTPUT_TYPE=splunk-hec IMAGE --config.test_and_exit
# A leading "logstash" arg is accepted and dropped. Any other command
# (e.g. "bash") is run as-is through the stock entrypoint.
set -euo pipefail

OUTPUT_TYPE="${OUTPUT_TYPE:-splunk-hec}"
CONFIG="/opt/configs/${OUTPUT_TYPE}-full.conf"
STOCK_ENTRYPOINT="/usr/local/bin/docker-entrypoint"

if [[ $# -gt 0 && "$1" != -* && "$1" != "logstash" ]]; then
  exec "$STOCK_ENTRYPOINT" "$@"
fi
if [[ "${1:-}" == "logstash" ]]; then
  shift
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: Unknown OUTPUT_TYPE: $OUTPUT_TYPE" >&2
  echo "Available types:" >&2
  for f in /opt/configs/*-full.conf; do
    [[ -f "$f" ]] && basename "$f" -full.conf >&2
  done
  exit 1
fi

# Splunk searches expect flattened suricata fields (same default as the
# splunk-hec docker_run.tftpl and the AWS task definitions). Override with
# -e FLATTEN_SURICATA=false.
if [[ "$OUTPUT_TYPE" == "splunk-hec" ]]; then
  export FLATTEN_SURICATA="${FLATTEN_SURICATA:-true}"
fi

echo "Starting Logstash with output type: $OUTPUT_TYPE"
# -f overrides pipelines.yml, so nothing is copied into pipeline/.
exec "$STOCK_ENTRYPOINT" -f "$CONFIG" "$@"

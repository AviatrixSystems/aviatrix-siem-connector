#!/bin/bash
set -e

OUTPUT_TYPE="${OUTPUT_TYPE:-splunk-hec}"
CONFIG="/opt/configs/${OUTPUT_TYPE}-full.conf"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: Unknown OUTPUT_TYPE: $OUTPUT_TYPE"
  echo "Available types:"
  ls /opt/configs/*-full.conf 2>/dev/null | xargs -n1 basename | sed 's/-full.conf//'
  exit 1
fi

echo "Starting Logstash with output type: $OUTPUT_TYPE"
cp "$CONFIG" /usr/share/logstash/pipeline/logstash.conf
exec /usr/share/logstash/bin/logstash

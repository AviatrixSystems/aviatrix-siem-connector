# Building custom container from Logstash container
# version 8.11+ is a logstash plugin requirement.
# More info at https://github.com/pkhabazi/microsoft-sentinel-logstash-output
FROM docker.elastic.co/logstash/logstash:8.16.2

# Install the Microsoft Sentinel Log Analytics output plugin for Logstash,
# enabling Logstash to send data directly to Azure Sentinel Log Analytics workspaces.
#
# For reproducible builds, pin the plugin version:
#   az acr build ... --build-arg SENTINEL_PLUGIN_VERSION=<x.y.z> .
#   docker build --build-arg SENTINEL_PLUGIN_VERSION=<x.y.z> .
# Leaving it empty installs the latest published version (not reproducible).
ARG SENTINEL_PLUGIN_VERSION=""
RUN if [ -n "$SENTINEL_PLUGIN_VERSION" ]; then \
      logstash-plugin install --version "$SENTINEL_PLUGIN_VERSION" microsoft-sentinel-log-analytics-logstash-output-plugin; \
    else \
      logstash-plugin install microsoft-sentinel-log-analytics-logstash-output-plugin; \
    fi

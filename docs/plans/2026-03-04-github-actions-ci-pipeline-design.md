# GitHub Actions CI Pipeline Design

**Date:** 2026-03-04
**Status:** Approved

## Goal

Ensure Logstash pipelines do not break with new commits. Validate config syntax for all output types and run end-to-end log processing with field extraction checks.

## Pipeline Structure

Single workflow (`.github/workflows/test-pipeline.yml`) with two jobs:

### Job 1: validate-configs (matrix)

Assembles and syntax-checks all 7 output types (excluding zabbix) in parallel.

**Matrix entries:**

| Output Type | Dummy Env Vars |
|---|---|
| splunk-hec | SPLUNK_ADDRESS, SPLUNK_PORT, SPLUNK_HEC_AUTH |
| azure-log-ingestion | client_app_id, client_app_secret, tenant_id, data_collection_endpoint, azure_dcr_*, azure_stream_*, azure_cloud |
| dynatrace | DT_METRICS_URL, DT_LOGS_URL, DT_API_TOKEN, DT_LOGS_TOKEN |
| dynatrace-metrics | DT_METRICS_URL, DT_API_TOKEN |
| dynatrace-logs | DT_LOGS_URL, DT_LOGS_TOKEN |
| webhook-test | WEBHOOK_URL |
| ci-test | (none) |

**Steps per matrix entry:**
1. Checkout repo
2. Run `assemble-config.sh <output-type>`
3. Run Logstash container with `--config.test_and_exit` and dummy env vars

### Job 2: e2e-pipeline-test (depends on Job 1)

Sends sample logs through Logstash and validates parsed output.

**New CI-specific output config** (`outputs/ci-test/output.conf`):
```
output {
  file {
    path => "/tmp/logstash-output.jsonl"
    codec => json_lines
  }
}
```

**Steps:**
1. Checkout repo
2. Assemble `ci-test` config via `assemble-config.sh`
3. Refresh sample log timestamps with `update-timestamps.py`
4. Start Logstash container in background with assembled config + patterns
5. Wait for Logstash to be ready (poll pipeline status or port)
6. Stream sample logs with `stream-logs.py` (UDP)
7. Wait for Logstash to flush output (check file stability)
8. Validate output with jq:
   - Total event count >= (input lines - known drops)
   - Each expected tag present: microseg, suricata, mitm, fqdn, cmd, gw_net_stats, gw_sys_stats, tunnel_status, vpn_session
   - No `_grokparsefailure` tags
   - `@timestamp` present on all events

## Workflow Triggers

- `pull_request` targeting `main`
- `push` to `main`
- **Path filter:** `logstash-configs/**`, `test-tools/sample-logs/**`, `.github/workflows/**`

## Performance

- Matrix validation: 7 configs in parallel (~2-3 min each)
- E2E test: ~3-4 min sequential (startup, streaming, flush, validation)
- Total wall time: ~5-6 min
- Runner: `ubuntu-latest`
- Logstash image: `docker.elastic.co/logstash/logstash:8.16.2`

## Excluded

- **Zabbix output**: requires custom Containerfile with plugin; excluded entirely
- **Real SIEM connectivity**: no live credentials in CI
- **Exact event count assertions**: use `>=` with known drop adjustments to avoid brittleness

## New Files

| File | Purpose |
|---|---|
| `.github/workflows/test-pipeline.yml` | CI workflow |
| `logstash-configs/outputs/ci-test/output.conf` | File output for E2E testing |

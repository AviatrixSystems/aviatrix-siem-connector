# Dynatrace Setup Guide

End-to-end guide for connecting the Aviatrix SIEM Connector to Dynatrace.

## 1. Token Setup

You need a **Platform token** (`dt0s16.*`) — not a classic API token (`dt0c01.*`).

1. In Dynatrace, go to **Account Management > Identity & access management > OAuth clients** or **Access Tokens**
2. Generate a new token with these scopes:

| Scope | Required For |
|-------|-------------|
| `storage:metrics:write` | Metrics ingest (gw_sys_stats, gw_net_stats) |
| `storage:logs:write` | Logs ingest (tunnel status, DCF events, IDS alerts, FQDN, controller audit) |

You can use a single token with both scopes, or separate tokens for metrics and logs.

> **Why not `dt0c01.*` tokens?** Classic API tokens authenticate against `.live.dynatrace.com/api/v2/` endpoints. Platform tokens (`dt0s16.*`) authenticate against `.apps.dynatrace.com/platform/classic/environment-api/v2/` endpoints. This integration uses platform tokens.

## 2. IAM Policy (Required)

Even with the correct token scopes, you'll get **403 "missing required permission"** unless the token's user group has an IAM policy bound.

1. Go to **Account Management > Identity & access management > Policies**
2. Create a new policy:
   - **Name**: `Aviatrix Log Integration` (or similar)
   - **Policy statement**:
     ```
     ALLOW storage:metrics:write, storage:logs:write;
     ```
3. Go to **Groups** and find the group your token's service user belongs to
4. Under **Permissions**, bind the policy to the appropriate environment

Without this step, the token has the scopes but lacks the IAM permission to use them.

## 3. URL Format

The ingest URLs follow this pattern:

```
https://{environment-id}.apps.dynatrace.com/platform/classic/environment-api/v2/metrics/ingest
https://{environment-id}.apps.dynatrace.com/platform/classic/environment-api/v2/logs/ingest
```

Find your `{environment-id}` in the Dynatrace URL bar (e.g., `abc12345` from `https://abc12345.apps.dynatrace.com/`).

> **Common mistake**: Do NOT use `https://{env-id}.live.dynatrace.com/api/v2/` — that endpoint only accepts classic `dt0c01.*` tokens and will return 401 for platform tokens.

## 4. Verify Before Deploying

Test both endpoints with curl before deploying Logstash.

### Test metrics ingest

```bash
export DT_METRICS_URL="https://<env-id>.apps.dynatrace.com/platform/classic/environment-api/v2/metrics/ingest"
export DT_API_TOKEN="dt0s16.YOUR_TOKEN..."

curl -s -o /dev/null -w "%{http_code}" -X POST "${DT_METRICS_URL}" \
  -H "Authorization: Bearer ${DT_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d "test.metric,gateway=\"test\" gauge,42 $(date +%s)000"
# Expect: 202
```

### Test logs ingest

```bash
export DT_LOGS_URL="https://<env-id>.apps.dynatrace.com/platform/classic/environment-api/v2/logs/ingest"
export DT_LOGS_TOKEN="dt0s16.YOUR_TOKEN..."

curl -s -o /dev/null -w "%{http_code}" -X POST "${DT_LOGS_URL}" \
  -H "Authorization: Bearer ${DT_LOGS_TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '[{"content":"test log","severity":"INFORMATIONAL","log.source":"aviatrix"}]'
# Expect: 204
```

If either returns a non-2xx status, see [Troubleshooting](#7-troubleshooting) below.

## 5. Choose an Output Variant

Three output configurations are available:

| Variant | Config | Use Case |
|---------|--------|----------|
| **`dynatrace`** (combined) | `./scripts/assemble-config.sh dynatrace` | Both metrics and logs from a single Logstash instance |
| **`dynatrace-metrics`** | `./scripts/assemble-config.sh dynatrace-metrics` | Metrics only (gw_sys_stats, gw_net_stats) |
| **`dynatrace-logs`** | `./scripts/assemble-config.sh dynatrace-logs` | Logs only (tunnel status, DCF, IDS, FQDN, controller audit) |

The **combined** variant is recommended for most deployments. Use the split variants when you need separate Logstash instances for metrics and logs (e.g., different scaling requirements).

## 6. Environment Variables

### Combined (`dynatrace`)

| Variable | Required | Description |
|----------|----------|-------------|
| `DT_METRICS_URL` | Yes | Metrics ingest URL (see [URL Format](#3-url-format)) |
| `DT_API_TOKEN` | Yes | Platform token with `storage:metrics:write` scope |
| `DT_LOGS_URL` | Yes | Logs ingest URL (see [URL Format](#3-url-format)) |
| `DT_LOGS_TOKEN` | Yes | Platform token with `storage:logs:write` scope |
| `DT_METRIC_SOURCE` | No | Source dimension for metrics (default: `aviatrix`) |
| `DT_LOG_SOURCE` | No | `log.source` attribute for logs (default: falls back to `DT_METRIC_SOURCE`) |
| `LOG_PROFILE` | No | Log type filter: `all` (default), `security`, or `networking` |

### Metrics-only (`dynatrace-metrics`)

| Variable | Required | Description |
|----------|----------|-------------|
| `DT_METRICS_URL` | Yes | Metrics ingest URL |
| `DT_API_TOKEN` | Yes | Platform token with `storage:metrics:write` scope |
| `DT_METRIC_SOURCE` | No | Source dimension (default: `aviatrix`) |
| `LOG_PROFILE` | No | `all` or `networking` (default: `all`) |

### Logs-only (`dynatrace-logs`)

| Variable | Required | Description |
|----------|----------|-------------|
| `DT_LOGS_URL` | Yes | Logs ingest URL |
| `DT_LOGS_TOKEN` | Yes | Platform token with `storage:logs:write` scope |
| `DT_LOG_SOURCE` | No | `log.source` attribute (default: `aviatrix`) |
| `LOG_PROFILE` | No | `all`, `security`, or `networking` (default: `all`) |

## 7. Troubleshooting

### Error Matrix

| HTTP Status | Error Message | Cause | Fix |
|-------------|---------------|-------|-----|
| **401** | Unauthorized | Platform token used against `.live.dynatrace.com` URL | Use `.apps.dynatrace.com/platform/classic/environment-api/v2/` URL instead |
| **403** | "missing required scope" | Token lacks the needed scope | Regenerate token with `storage:metrics:write` and/or `storage:logs:write` |
| **403** | "missing required permission" | IAM policy not bound to user group | Create IAM policy with `ALLOW storage:metrics:write, storage:logs:write;` and bind to group (see [Step 2](#2-iam-policy-required)) |
| **404** | Not found | Wrong URL path | Use `/platform/classic/environment-api/v2/` not `/api/v2/` |

### Metrics not appearing

1. Verify `DT_METRICS_URL` and `DT_API_TOKEN` are set
2. Run the [metrics curl test](#test-metrics-ingest) — expect 202
3. Check Logstash logs: `docker logs <container>`
4. Verify filter 94 (`94-save-raw-net-rates.conf`) is present for accurate rate values
5. Check `LOG_PROFILE` allows `networking` or `all`

### Logs not appearing

1. Verify `DT_LOGS_URL` and `DT_LOGS_TOKEN` are set
2. Run the [logs curl test](#test-logs-ingest) — expect 204
3. Check Logstash logs: `docker logs <container>`
4. Check `LOG_PROFILE` includes the desired log types

## 8. Where to Find Data in Dynatrace

### Metrics

- **Observe > Explore**: Search for `aviatrix.gateway.*`
- **DQL**:
  ```
  timeseries avg(aviatrix.gateway.cpu.usage), by:{gateway}
  timeseries avg(aviatrix.gateway.memory.usage), by:{gateway}
  timeseries avg(aviatrix.gateway.net.bytes_rx), by:{gateway, interface}
  ```

### Logs

- **Observe > Logs**: Filter by `log.source = "aviatrix"`
- **DQL**:
  ```
  fetch logs
  | filter log.source == "aviatrix"
  | sort timestamp desc

  fetch logs
  | filter aviatrix.event.type == "TunnelStatus"
  | filter aviatrix.tunnel.new_state == "Down"
  | sort timestamp desc

  fetch logs
  | filter aviatrix.event.type == "IDSAlert"
  | summarize count(), by:{aviatrix.ids.severity, aviatrix.ids.category}
  ```

See the individual output READMEs for the full metrics reference and log attribute reference:
- [Metrics reference](../logstash-configs/outputs/dynatrace-metrics/README.md)
- [Logs reference](../logstash-configs/outputs/dynatrace-logs/README.md)
- [Combined output](../logstash-configs/outputs/dynatrace/README.md)

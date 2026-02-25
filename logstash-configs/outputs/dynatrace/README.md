# Dynatrace Combined Output (Metrics + Logs)

Sends both gateway metrics and event logs to Dynatrace from a single Logstash instance:

- **Metrics** (MINT line protocol) -> `/api/v2/metrics/ingest` — CPU, memory, disk, network stats
- **Logs** (JSON) -> `/api/v2/logs/ingest` — tunnel status, DCF events, IDS alerts, FQDN, controller audit

## Prerequisites

1. **Dynatrace Environment** with metrics and logs ingest endpoints
2. **Platform token(s)** (`dt0s16.*`) with `storage:metrics:write` and `storage:logs:write` scopes
3. **IAM policy** bound to the token's user group granting write permissions

See the [Dynatrace Setup Guide](../../../docs/DYNATRACE_SETUP.md) for step-by-step token, IAM policy, and URL configuration.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DT_METRICS_URL` | Yes | — | Metrics ingest endpoint (e.g., `https://<env-id>.apps.dynatrace.com/platform/classic/environment-api/v2/metrics/ingest`) |
| `DT_API_TOKEN` | Yes | — | Platform token with `storage:metrics:write` scope |
| `DT_LOGS_URL` | Yes | — | Logs ingest endpoint (e.g., `https://<env-id>.apps.dynatrace.com/platform/classic/environment-api/v2/logs/ingest`) |
| `DT_LOGS_TOKEN` | Yes | — | Platform token with `storage:logs:write` scope |
| `DT_METRIC_SOURCE` | No | `aviatrix` | Source dimension for metrics |
| `DT_LOG_SOURCE` | No | (falls back to `DT_METRIC_SOURCE`) | `log.source` attribute for logs |
| `LOG_PROFILE` | No | `all` | Log type filter: `all`, `security`, or `networking` |

## Quick Start

```bash
cd logstash-configs
./scripts/assemble-config.sh dynatrace
```

This creates `assembled/dynatrace-full.conf`.

## Data Flow

```
Aviatrix Gateways (syslog UDP/TCP 5000)
         |
    Logstash Pipeline
         |
    +----+----+
    |         |
  [Stats]   [Events]
    |         |
  MINT       JSON
  Builder    Builder
    |         |
  HTTP OUT   HTTP OUT
  text/plain application/json
    |         |
  /metrics/  /logs/
  ingest     ingest
```

### Metrics Pipeline (gw_sys_stats, gw_net_stats)

See [dynatrace-metrics README](../dynatrace-metrics/README.md) for the full metrics reference.

### Logs Pipeline

| Tag | Event Type | Severity | Profile |
|-----|-----------|----------|---------|
| `tunnel_status` | TunnelStatus | Down=WARN, Up=INFO | networking |
| `microseg` | DCFPolicyEvent | DENY=WARN, ALLOW=INFO | security |
| `mitm` | WebInspection | DENY=WARN, ALLOW=INFO | security |
| `suricata` | IDSAlert | sev1=ERROR, sev2=WARN, sev3+=INFO | security |
| `fqdn` | FQDNFilter | blocked=WARN, else=INFO | security |
| `cmd` | ControllerAudit | !Success=WARN, else=INFO | security |

See [dynatrace-logs README](../dynatrace-logs/README.md) for the full attribute reference and DQL queries.

## LOG_PROFILE Routing

| Profile | Metrics | Logs |
|---------|---------|------|
| `all` | gw_sys_stats, gw_net_stats | All 6 event types |
| `networking` | gw_sys_stats, gw_net_stats | tunnel_status only |
| `security` | (none) | suricata, mitm, microseg, fqdn, cmd |

## Correlation Between Metrics and Logs

Shared identifiers enable cross-referencing in Dynatrace dashboards:

| Concept | Metrics Dimension | Logs Attribute |
|---------|-------------------|----------------|
| Gateway | `gateway="k8s-transit"` | `aviatrix.tunnel.src_gw="k8s-transit"` |
| Source | `source="aviatrix"` | `log.source="aviatrix"` |
| Cloud | (if added) | `cloud.provider="aws"` |
| Region | (if added) | `cloud.region="us-east-2"` |

Example dashboard layout:
- **Panel 1** (metric chart): `aviatrix.gateway.cpu.usage` filtered by `gateway="k8s-transit"`
- **Panel 2** (log table): `fetch logs | filter aviatrix.tunnel.src_gw == "k8s-transit"`
- **Shared time selector** for correlated view

## Troubleshooting

### Only metrics arriving (no logs)

1. Verify `DT_LOGS_URL` and `DT_LOGS_TOKEN` are set
2. Verify token has `storage:logs:write` scope and IAM policy is bound
3. Check LOG_PROFILE includes the desired log types

### Only logs arriving (no metrics)

1. Verify `DT_METRICS_URL` and `DT_API_TOKEN` are set
2. Verify token has `storage:metrics:write` scope and IAM policy is bound
3. Verify filter 94 (`94-save-raw-net-rates.conf`) is present for accurate rate conversion
4. Check LOG_PROFILE allows `networking` or `all`

### 401/403/404 errors

See the [troubleshooting matrix](../../../docs/DYNATRACE_SETUP.md#7-troubleshooting) in the setup guide.

### Splitting into separate deployments

If you prefer separate Logstash instances:
- Metrics only: `./scripts/assemble-config.sh dynatrace-metrics`
- Logs only: `./scripts/assemble-config.sh dynatrace-logs`

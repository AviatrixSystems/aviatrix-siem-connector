# Aviatrix → Microsoft Sentinel — Demo Runbook

A customer-facing demo showing Aviatrix Distributed Cloud Firewall telemetry living inside
Microsoft Sentinel: a 5-tab workbook plus analytics rules that turn Aviatrix IDS alerts into
real Sentinel Incidents.

## What's deployed

| Artifact | Name | Notes |
|---|---|---|
| Workbook | **Aviatrix Security (Sentinel Demo)** | 5 tabs: Overview (SOC triage), DCF Policy, Threats (IDS), Traffic & Egress, Gateway Health |
| Analytics rule | **Aviatrix IDS: high-severity intrusion detected** | Severity 1–2 IDS alert → Sentinel Incident (hero moment) |
| Analytics rule | **Aviatrix DCF: repeated egress denied to a destination FQDN** | ≥5 DCF denies to one FQDN → Sentinel Incident |

Workspace: `aviatrix-siem-workspace` (RG `aviatrix-siem-connector`).

## Deploy / redeploy

```bash
cd logstash-configs/outputs/azure-log-ingestion/sentinel-demo
WS_RG=aviatrix-siem-connector WS_NAME=aviatrix-siem-workspace \
SUB=a9b9847f-ac2a-4fe8-95c7-727057b7e2e4 ./deploy.sh
```

The script is idempotent: it onboards Sentinel if needed, then upserts the workbook and both
rules.

## Prerequisites for a full demo

1. **Sentinel enabled** on the workspace (the deploy script does this).
2. **Connector running** — the ACI container receiving syslog at
   `aviatrix-logstash-sentinel-62054.eastus.azurecontainer.io:5000` (TCP).
3. **Lab fabric features** pointed at the connector FQDN. Each feeds specific tabs:

   | Enable in the lab | Populates |
   |---|---|
   | DCF L4 microseg with **deny** policies | Overview, DCF Policy, Traffic |
   | DCF L7 with **TLS inspection** (MITM) | Overview, DCF Policy, Traffic (domains) |
   | **Suricata IDS** | Overview, Threats, **both analytics rules** |
   | Gateway syslog → connector FQDN | All tabs (gateway stats already flow) |

> Gateway Health populates from data already flowing today. The security tabs fill in once the
> lab generates microseg/MITM/IDS events.

## Demo arc (~5 minutes)

1. **Open the workbook** (Sentinel → Workbooks → *Aviatrix Security (Sentinel Demo)*). Land on
   **Overview**: "This is your Aviatrix fabric, live in Microsoft Sentinel."
2. **Generate lab traffic**: one flow that DCF blocks (egress to a denied FQDN) and one that
   trips Suricata IDS.
3. **Watch the Overview threat feed** light up with the new IDS alert and DCF deny.
4. **Pivot to the Threats (IDS) tab** — drill into the signature, source, and target.
5. **Show the auto-created Sentinel Incident** (Sentinel → Incidents → *Aviatrix IDS:
   high-severity intrusion detected*) with mapped source/destination IP entities.
6. **Close on the DCF Policy tab**: "Aviatrix enforced the policy, and Sentinel correlated it
   into an incident — no extra agents, just your existing SIEM."

## Troubleshooting

- **Empty security tabs / no incident:** the lab feature isn't enabled or isn't syslogging to
  the connector. Gateway Health should always have data; if it doesn't, the connector itself
  isn't receiving logs.
- **Ingestion latency:** allow ~2–10 minutes between lab traffic and data appearing in Log
  Analytics; the analytics rules run every 5 minutes. Generate traffic early in the arc.
- **Incident not firing:** confirm an IDS event with severity 1 or 2 (`AviatrixIDS_CL | where
  toint(ThreatRiskLevel) in (1,2)`), and that the rule is enabled.
- **Severity field:** the IDS rule keys on `ThreatRiskLevel` (1–4). If your build maps Suricata
  severity differently, adjust the `query` in `analytics-rules/ids-high-severity.json`.

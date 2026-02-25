import { LogType } from "./types";

/**
 * Maps Logstash plugin IDs to log types.
 * Plugin IDs come from the `id =>` directives in all Logstash filter and output configs.
 */

// Shared filter plugin IDs (used by all output types)
const FILTER_PLUGIN_MAP: Record<string, LogType> = {
  // microseg filters
  microseg: "microseg",
  "microseg-legacy-defaults": "microseg",
  "microseg-field-conversion": "microseg",

  // mitm filters
  mitm: "mitm",
  "mitm-json": "mitm",
  "mitm-timestamp": "mitm",
  "mitm-map-to-microseg": "mitm",
  "mitm-map-drop-to-deny": "mitm",
  "mitm-url-parts": "mitm",
  "mitm-decrypted-by": "mitm",
  "mitm-field-conversion": "mitm",

  // suricata filters
  suricata: "suricata",
  "suricata-data": "suricata",
  "suricata-process": "suricata",

  // fqdn filters
  fqdn: "fqdn",

  // cmd filters
  "cmd-v1": "cmd",
  "cmd-set-hostname": "cmd",
  "cmd-default-reason": "cmd",
  "cmd-v2": "cmd",

  // gw_net_stats filters
  gw_net_stats: "gw_net_stats",
  "gw_net_stats-rate-conversion": "gw_net_stats",
  "save-raw-net-rates": "gw_net_stats",

  // gw_sys_stats filters
  gw_sys_stats: "gw_sys_stats",
  "gw_sys_stats-field-conversion": "gw_sys_stats",
  "cpu-cores-parse": "gw_sys_stats",
  "sys-stats-hec-payload": "gw_sys_stats",

  // tunnel_status filters
  tunnel_status: "tunnel_status",
};

// Output plugin IDs grouped by output type
const OUTPUT_PLUGIN_MAP: Record<string, LogType> = {
  // Splunk HEC
  "splunk-microseg": "microseg",
  "splunk-mitm": "mitm",
  "splunk-suricata": "suricata",
  "splunk-fqdn": "fqdn",
  "splunk-cmd": "cmd",
  "splunk-gw-net-stats": "gw_net_stats",
  "splunk-gw-sys-stats": "gw_sys_stats",
  "splunk-tunnel-status": "tunnel_status",

  // Azure Log Ingestion
  "azure-microseg": "microseg",
  "azure-mitm": "mitm",
  "azure-suricata": "suricata",
  "azure-gw-net-stats": "gw_net_stats",
  "azure-gw-sys-stats": "gw_sys_stats",
  "azure-cmd": "cmd",
  "azure-tunnel-status": "tunnel_status",

  // Webhook Test
  "webhook-microseg": "microseg",
  "webhook-mitm": "mitm",
  "webhook-suricata": "suricata",
  "webhook-fqdn": "fqdn",
  "webhook-cmd": "cmd",
  "webhook-gw-net-stats": "gw_net_stats",
  "webhook-gw-sys-stats": "gw_sys_stats",
  "webhook-tunnel-status": "tunnel_status",

  // Dynatrace (combined/logs/metrics)
  "dynatrace-build-microseg-log": "microseg",
  "dynatrace-build-mitm-log": "mitm",
  "dynatrace-build-suricata-log": "suricata",
  "dynatrace-build-fqdn-log": "fqdn",
  "dynatrace-build-cmd-log": "cmd",
  "dynatrace-build-tunnel-status-log": "tunnel_status",
  "dynatrace-build-net-stats-mint": "gw_net_stats",
  "dynatrace-build-sys-stats-mint": "gw_sys_stats",
};

// Azure ASIM filter IDs (processed only in Azure pipeline)
const AZURE_FILTER_MAP: Record<string, LogType> = {
  "suricata-azure-flatten": "suricata",
  "suricata-asim-common": "suricata",
  "suricata-asim-mapping": "suricata",
  "suricata-azure-cleanup": "suricata",
  "suricata-asim-int-coerce": "suricata",
  "microseg-asim-common": "microseg",
  "microseg-asim-mapping": "microseg",
  "microseg-azure-cleanup": "microseg",
  "microseg-asim-int-coerce": "microseg",
  "mitm-asim-common": "mitm",
  "mitm-asim-mapping": "mitm",
  "mitm-azure-cleanup": "mitm",
  "mitm-asim-int-coerce": "mitm",
  "gw-net-stats-azure-timegen": "gw_net_stats",
  "gw-net-stats-azure-cleanup": "gw_net_stats",
  "gw-sys-stats-azure-timegen": "gw_sys_stats",
  "gw-sys-stats-azure-cleanup": "gw_sys_stats",
  "cmd-azure-timegen": "cmd",
  "cmd-azure-cleanup": "cmd",
  "tunnel-status-azure-timegen": "tunnel_status",
  "tunnel-status-azure-cleanup": "tunnel_status",
};

// Drop filter IDs with log type and human-readable reason
const DROP_PLUGIN_MAP: Record<string, { logType: LogType; reason: string }> = {
  "suricata-non-json-drop": { logType: "suricata", reason: "Non-JSON/notices" },
  "suricata-json-failure-drop": { logType: "suricata", reason: "Parse failures" },
  "suricata-stats-drop": { logType: "suricata", reason: "Stats filtered" },
};

const DROP_PLUGIN_IDS = new Set(Object.keys(DROP_PLUGIN_MAP));

const THROTTLE_PLUGIN_IDS = new Set<string>();

// Global filter IDs (not log-type specific)
const GLOBAL_FILTER_IDS = new Set([
  "date-to-timestamp",
  "add-unix-time",
]);

// Output type detection: which output plugin ID prefixes identify each type
const OUTPUT_TYPE_PREFIXES: Record<string, string> = {
  "splunk-": "splunk-hec",
  "azure-": "azure-log-ingestion",
  "webhook-": "webhook-test",
  "dynatrace-metrics": "dynatrace-metrics",
  "dynatrace-logs": "dynatrace-logs",
  "dynatrace-": "dynatrace",
};

// Shared output IDs used by multiple log types
const SHARED_OUTPUT_IDS: Record<string, LogType[]> = {
  "dynatrace-logs": ["microseg", "mitm", "suricata", "fqdn", "cmd", "tunnel_status"],
  "dynatrace-metrics": ["gw_net_stats", "gw_sys_stats"],
};

// Build drop plugin → log type map for inclusion in ALL_PLUGIN_MAP
const DROP_LOGTYPE_MAP: Record<string, LogType> = Object.fromEntries(
  Object.entries(DROP_PLUGIN_MAP).map(([id, { logType }]) => [id, logType]),
);

const ALL_PLUGIN_MAP: Record<string, LogType> = {
  ...FILTER_PLUGIN_MAP,
  ...DROP_LOGTYPE_MAP,
  ...OUTPUT_PLUGIN_MAP,
  ...AZURE_FILTER_MAP,
};

/** Look up the log type for a plugin ID */
export function getLogType(pluginId: string): LogType | null {
  return ALL_PLUGIN_MAP[pluginId] ?? null;
}

/** Check if a plugin ID represents a drop action */
export function isDropPlugin(pluginId: string): boolean {
  return DROP_PLUGIN_IDS.has(pluginId);
}

/** Check if a plugin ID represents throttling */
export function isThrottlePlugin(pluginId: string): boolean {
  return THROTTLE_PLUGIN_IDS.has(pluginId);
}

/** Get the human-readable drop reason for a drop plugin ID */
export function getDropReason(pluginId: string): string | null {
  return DROP_PLUGIN_MAP[pluginId]?.reason ?? null;
}

/** Check if a plugin is a global/shared filter (not log-type specific) */
export function isGlobalFilter(pluginId: string): boolean {
  return GLOBAL_FILTER_IDS.has(pluginId);
}

/** Check if a plugin ID is an output plugin */
export function isOutputPlugin(pluginId: string): boolean {
  return pluginId in OUTPUT_PLUGIN_MAP;
}

/** Check if a plugin ID is a shared output (serves multiple log types) */
export function getSharedOutputLogTypes(pluginId: string): LogType[] | null {
  return SHARED_OUTPUT_IDS[pluginId] ?? null;
}

/** Auto-detect the output type from the set of output plugin IDs present */
export function detectOutputType(outputPluginIds: string[]): string {
  for (const id of outputPluginIds) {
    for (const [prefix, outputType] of Object.entries(OUTPUT_TYPE_PREFIXES)) {
      if (id.startsWith(prefix)) {
        return outputType;
      }
    }
  }
  return "unknown";
}

/** Get the destination description for an output type */
export function getDestinationLabel(outputType: string): string {
  switch (outputType) {
    case "splunk-hec":
      return `Splunk HEC → ${process.env.SPLUNK_ADDRESS || "unknown"}:${process.env.SPLUNK_PORT || "8088"}`;
    case "azure-log-ingestion":
      return `Azure Log Analytics → ${process.env.data_collection_endpoint || "unknown"}`;
    case "webhook-test":
      return `Webhook → ${process.env.WEBHOOK_URL || "http://localhost:8080"}`;
    case "dynatrace":
    case "dynatrace-logs":
    case "dynatrace-metrics":
      return `Dynatrace → ${process.env.DT_METRICS_URL || process.env.DT_LOGS_URL || "unknown"}`;
    default:
      return outputType;
  }
}

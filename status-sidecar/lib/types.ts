export type HealthStatus = "healthy" | "degraded" | "unhealthy";

export type LogType =
  | "microseg"
  | "mitm"
  | "suricata"
  | "fqdn"
  | "cmd"
  | "gw_net_stats"
  | "gw_sys_stats"
  | "tunnel_status";

export const LOG_TYPE_LABELS: Record<LogType, string> = {
  microseg: "L4 Microseg",
  mitm: "L7 MITM/DCF",
  suricata: "Suricata IDS",
  fqdn: "FQDN Firewall",
  cmd: "Controller CMD",
  gw_net_stats: "GW Net Stats",
  gw_sys_stats: "GW Sys Stats",
  tunnel_status: "Tunnel Status",
};

export interface HealthResult {
  status: HealthStatus;
  reasons: string[];
}

export interface MetricsSample {
  timestamp: number;
  jvm: {
    heapUsedBytes: number;
    heapMaxBytes: number;
    heapUsedPercent: number;
    gcCollectionTimeMs: number;
    gcCollectionCount: number;
    uptimeMs: number;
  };
  process: {
    cpuPercent: number;
    openFileDescriptors: number;
    maxFileDescriptors: number;
    memTotalVirtualBytes: number;
  };
  pipeline: {
    events: {
      in: number;
      out: number;
      filtered: number;
      durationMs: number;
      queuePushDurationMs: number;
    };
    queue: {
      events: number;
      type: string;
      capacity?: {
        maxQueueSizeBytes?: number;
        queueSizeBytes?: number;
      };
    };
    plugins: {
      filters: PluginStat[];
      outputs: PluginStat[];
    };
    reloads: {
      successes: number;
      failures: number;
      lastSuccessTimestamp?: string;
      lastFailureTimestamp?: string;
    };
  };
  dlq?: {
    queueSizeBytes: number;
    maxQueueSizeBytes: number;
    droppedEvents: number;
    expiredEvents: number;
  };
}

export interface PluginStat {
  id: string;
  name: string;
  events: {
    in: number;
    out: number;
    durationMs: number;
  };
  failures?: number;
}

export interface MetricsDelta {
  timestamp: number;
  intervalSecs: number;
  inputEps: number;
  outputEps: number;
  pipeline: {
    eventsIn: number;
    eventsOut: number;
  };
}

export interface DropReason {
  reason: string;
  count: number;
}

export interface LogTypeDelta {
  logType: LogType;
  received: number;
  dropped: number;
  dropReasons: DropReason[];
  sent: number;
  failed: number;
  eps: number;
}

export interface PipelineConfig {
  workers: number;
  batchSize: number;
  batchDelay: number;
  queueType: string;
  dlqEnabled: boolean;
}

export interface StatsSnapshot {
  health: HealthResult;
  outputType: string;
  destination: string;
  logProfile: string;
  uptime: string;
  version: string;
  pipeline: {
    eventsIn: number;
    eventsOut: number;
    inputEps: number;
    outputEps: number;
    avgEps1h: number;
    queueEvents: number;
    queueSizeBytes: number;
    queueMaxBytes: number;
    queueType: string;
  };
  jvm: {
    heapUsedBytes: number;
    heapMaxBytes: number;
    heapUsedPercent: number;
    gcCollectionTimeMs: number;
    gcCollectionCount: number;
  };
  process: {
    cpuPercent: number;
    openFileDescriptors: number;
    maxFileDescriptors: number;
  };
  dlq: {
    queueSizeBytes: number;
    maxQueueSizeBytes: number;
    droppedEvents: number;
    expiredEvents: number;
  };
  logTypes: LogTypeDelta[];
  config: PipelineConfig;
}

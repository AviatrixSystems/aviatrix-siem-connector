import { getNodeStats, getNodeInfo } from "./logstash-client";
import { evaluateHealth } from "./health-evaluator";
import {
  getLogType,
  isOutputPlugin,
  isDropPlugin,
  getDropReason,
  detectOutputType,
  getDestinationLabel,
  getSharedOutputLogTypes,
} from "./plugin-map";
import type {
  MetricsSample,
  MetricsDelta,
  LogTypeDelta,
  DropReason,
  PluginStat,
  PipelineConfig,
  StatsSnapshot,
  HealthResult,
  LogType,
} from "./types";

const BUFFER_SIZE = 720; // 60s intervals × 720 = 12 hours
const POLL_INTERVAL_MS = 60_000; // Full metrics every 60s
const HEALTH_INTERVAL_MS = 10_000; // Lightweight health every 10s

/* eslint-disable @typescript-eslint/no-explicit-any */
function extractSample(raw: any): MetricsSample {
  const jvm = raw.jvm;
  const proc = raw.process;
  const pipe =
    raw.pipelines?.main ?? raw.pipeline ?? Object.values(raw.pipelines ?? {})[0];
  const queue = pipe?.queue ?? {};
  const reloads = pipe?.reloads ?? {};

  return {
    timestamp: Date.now(),
    jvm: {
      heapUsedBytes: jvm?.mem?.heap_used_in_bytes ?? 0,
      heapMaxBytes: jvm?.mem?.heap_max_in_bytes ?? 1,
      heapUsedPercent: jvm?.mem?.heap_used_percent ?? 0,
      gcCollectionTimeMs:
        Object.values(jvm?.gc?.collectors ?? {}).reduce(
          (sum: number, c: any) => sum + (c.collection_time_in_millis ?? 0),
          0,
        ) ?? 0,
      gcCollectionCount:
        Object.values(jvm?.gc?.collectors ?? {}).reduce(
          (sum: number, c: any) => sum + (c.collection_count ?? 0),
          0,
        ) ?? 0,
      uptimeMs: jvm?.uptime_in_millis ?? 0,
    },
    process: {
      cpuPercent: proc?.cpu?.percent ?? 0,
      openFileDescriptors: proc?.open_file_descriptors ?? 0,
      maxFileDescriptors: proc?.max_file_descriptors ?? 0,
      memTotalVirtualBytes: proc?.mem?.total_virtual_in_bytes ?? 0,
    },
    pipeline: {
      events: {
        in: pipe?.events?.in ?? 0,
        out: pipe?.events?.out ?? 0,
        filtered: pipe?.events?.filtered ?? 0,
        durationMs: pipe?.events?.duration_in_millis ?? 0,
        queuePushDurationMs:
          pipe?.events?.queue_push_duration_in_millis ?? 0,
      },
      queue: {
        events: queue?.events_count ?? queue?.events ?? 0,
        type: queue?.type ?? "memory",
        capacity: queue?.capacity
          ? {
              maxQueueSizeBytes: queue.capacity.max_queue_size_in_bytes,
              queueSizeBytes: queue.capacity.queue_size_in_bytes,
            }
          : undefined,
      },
      plugins: {
        filters: (pipe?.plugins?.filters ?? []).map((f: any) => ({
          id: f.id ?? "",
          name: f.name ?? "",
          events: {
            in: f.events?.in ?? 0,
            out: f.events?.out ?? 0,
            durationMs: f.events?.duration_in_millis ?? 0,
          },
          failures: f.failures,
        })),
        outputs: (pipe?.plugins?.outputs ?? []).map((o: any) => ({
          id: o.id ?? "",
          name: o.name ?? "",
          events: {
            in: o.events?.in ?? 0,
            out: o.events?.out ?? 0,
            durationMs: o.events?.duration_in_millis ?? 0,
          },
          failures: o.failures,
        })),
      },
      reloads: {
        successes: reloads?.successes ?? 0,
        failures: reloads?.failures ?? 0,
        lastSuccessTimestamp: reloads?.last_success_timestamp,
        lastFailureTimestamp: reloads?.last_failure_timestamp,
      },
    },
    dlq: raw.dead_letter_queue
      ? {
          queueSizeBytes: raw.dead_letter_queue.queue_size_in_bytes ?? 0,
          maxQueueSizeBytes:
            raw.dead_letter_queue.max_queue_size_in_bytes ?? 0,
          droppedEvents: raw.dead_letter_queue.dropped_events ?? 0,
          expiredEvents: raw.dead_letter_queue.expired_events ?? 0,
        }
      : undefined,
  };
}
/* eslint-enable @typescript-eslint/no-explicit-any */

function computeDelta(prev: MetricsSample, curr: MetricsSample): MetricsDelta {
  const intervalSecs = (curr.timestamp - prev.timestamp) / 1000;
  const evIn = curr.pipeline.events.in - prev.pipeline.events.in;
  const evOut = curr.pipeline.events.out - prev.pipeline.events.out;

  return {
    timestamp: curr.timestamp,
    intervalSecs,
    inputEps: intervalSecs > 0 ? evIn / intervalSecs : 0,
    outputEps: intervalSecs > 0 ? evOut / intervalSecs : 0,
    pipeline: { eventsIn: evIn, eventsOut: evOut },
  };
}

function computeLogTypeCumulatives(
  curr: MetricsSample,
  prev: MetricsSample | null,
): LogTypeDelta[] {
  const types: LogType[] = [
    "microseg",
    "mitm",
    "suricata",
    "fqdn",
    "cmd",
    "gw_net_stats",
    "gw_sys_stats",
    "tunnel_status",
  ];

  const intervalSecs =
    prev ? (curr.timestamp - prev.timestamp) / 1000 : 1;

  return types.map((logType) => {
    let sent = 0;
    let dropped = 0;
    let failed = 0;
    const dropReasonsMap: Record<string, number> = {};

    // Dropped events from drop/throttle filter plugins
    for (const f of curr.pipeline.plugins.filters) {
      const fType = getLogType(f.id);
      if (fType !== logType) continue;
      if (isDropPlugin(f.id)) {
        const count = f.events.in;
        dropped += count;
        const reason = getDropReason(f.id) ?? f.id;
        dropReasonsMap[reason] = (dropReasonsMap[reason] ?? 0) + count;
      }
    }

    // Output plugin stats: events.out = successfully sent, failures = delivery errors
    for (const o of curr.pipeline.plugins.outputs) {
      if (!isOutputPlugin(o.id)) continue;

      const oType = getLogType(o.id);
      const sharedTypes = getSharedOutputLogTypes(o.id);
      if (oType !== logType && !(sharedTypes && sharedTypes.includes(logType)))
        continue;

      sent += o.events.out;
      failed += o.failures ?? 0;
    }

    // Received = everything that entered the pipeline for this type
    // (events that were sent + dropped + failed to deliver)
    const received = sent + dropped + failed;

    // Build sorted drop reasons array
    const dropReasons: DropReason[] = Object.entries(dropReasonsMap)
      .filter(([, count]) => count > 0)
      .map(([reason, count]) => ({ reason, count }))
      .sort((a, b) => b.count - a.count);

    // EPS from most recent delta interval
    let eps = 0;
    if (prev && intervalSecs > 0) {
      let prevSent = 0;
      for (const o of prev.pipeline.plugins.outputs) {
        if (!isOutputPlugin(o.id)) continue;
        const oType = getLogType(o.id);
        const sharedTypes = getSharedOutputLogTypes(o.id);
        if (oType !== logType && !(sharedTypes && sharedTypes.includes(logType)))
          continue;
        prevSent += o.events.out;
      }
      eps = (sent - prevSent) / intervalSecs;
    }

    return { logType, received, dropped, dropReasons, sent, failed, eps };
  });
}

class MetricsStore {
  private buffer: MetricsSample[] = [];
  private deltas: MetricsDelta[] = [];
  private latest: MetricsSample | null = null;
  private lastContactMs: number = 0;
  private pipelineConfig: PipelineConfig | null = null;
  private detectedOutputType: string = "unknown";
  private version: string = "";
  private logTypeDeltas: LogTypeDelta[] = [];
  private started = false;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private healthTimer: ReturnType<typeof setInterval> | null = null;

  start() {
    if (this.started) return;
    this.started = true;

    // Fetch node info once for pipeline config
    this.fetchNodeInfo();

    // Start polling loops
    this.pollFull();
    this.pollTimer = setInterval(() => this.pollFull(), POLL_INTERVAL_MS);
    this.healthTimer = setInterval(
      () => this.pollHealth(),
      HEALTH_INTERVAL_MS,
    );
  }

  stop() {
    if (this.pollTimer) clearInterval(this.pollTimer);
    if (this.healthTimer) clearInterval(this.healthTimer);
    this.started = false;
  }

  private async fetchNodeInfo() {
    try {
      const info = await getNodeInfo();
      const pipe =
        info.pipelines?.main ?? Object.values(info.pipelines ?? {})[0];
      if (pipe) {
        this.pipelineConfig = {
          workers: pipe.workers ?? 0,
          batchSize: pipe.batch_size ?? 0,
          batchDelay: pipe.batch_delay ?? 0,
          queueType: pipe.queue?.type ?? "memory",
          dlqEnabled: pipe.dead_letter_queue_enabled ?? false,
        };
      }
      this.version = info.version ?? "";
    } catch {
      // Will retry on next poll
    }
  }

  private async pollFull() {
    try {
      const raw = await getNodeStats();
      const sample = extractSample(raw);
      const prev = this.latest;
      this.latest = sample;
      this.lastContactMs = Date.now();

      // Push to circular buffer
      this.buffer.push(sample);
      if (this.buffer.length > BUFFER_SIZE) {
        this.buffer.shift();
      }

      // Compute delta
      if (prev) {
        const delta = computeDelta(prev, sample);
        this.deltas.push(delta);
        if (this.deltas.length > BUFFER_SIZE) {
          this.deltas.shift();
        }
      }

      // Compute cumulative log type stats
      this.logTypeDeltas = computeLogTypeCumulatives(sample, prev);

      // Auto-detect output type from output plugin IDs
      if (this.detectedOutputType === "unknown") {
        const outputIds = sample.pipeline.plugins.outputs.map((o) => o.id);
        this.detectedOutputType = detectOutputType(outputIds);
      }
    } catch {
      // Connection failure — health evaluator will detect via lastContactMs
    }
  }

  private async pollHealth() {
    // Lightweight: just try to reach the API
    try {
      await getNodeStats();
      this.lastContactMs = Date.now();
    } catch {
      // Will be detected by health evaluator
    }
  }

  getHealth(): HealthResult {
    return evaluateHealth(
      this.latest,
      this.deltas.slice(-10),
      this.lastContactMs,
      Date.now(),
    );
  }

  getStats(): StatsSnapshot {
    const health = this.getHealth();
    const current = this.latest;

    // Compute 1h average EPS
    const oneHourAgo = Date.now() - 3600_000;
    const recentDeltas = this.deltas.filter((d) => d.timestamp > oneHourAgo);
    const avgEps1h =
      recentDeltas.length > 0
        ? recentDeltas.reduce((s, d) => s + d.outputEps, 0) /
          recentDeltas.length
        : 0;

    // Current EPS from latest delta
    const latestDelta = this.deltas[this.deltas.length - 1];

    return {
      health,
      outputType: this.detectedOutputType,
      destination: getDestinationLabel(this.detectedOutputType),
      logProfile: process.env.LOG_PROFILE || "all",
      uptime: current ? formatUptime(current.jvm.uptimeMs) : "0s",
      version: this.version,
      pipeline: {
        eventsIn: current?.pipeline.events.in ?? 0,
        eventsOut: current?.pipeline.events.out ?? 0,
        inputEps: latestDelta?.inputEps ?? 0,
        outputEps: latestDelta?.outputEps ?? 0,
        avgEps1h,
        queueEvents: current?.pipeline.queue.events ?? 0,
        queueSizeBytes:
          current?.pipeline.queue.capacity?.queueSizeBytes ?? 0,
        queueMaxBytes:
          current?.pipeline.queue.capacity?.maxQueueSizeBytes ?? 0,
        queueType: current?.pipeline.queue.type ?? "memory",
      },
      jvm: {
        heapUsedBytes: current?.jvm.heapUsedBytes ?? 0,
        heapMaxBytes: current?.jvm.heapMaxBytes ?? 0,
        heapUsedPercent: current?.jvm.heapUsedPercent ?? 0,
        gcCollectionTimeMs: current?.jvm.gcCollectionTimeMs ?? 0,
        gcCollectionCount: current?.jvm.gcCollectionCount ?? 0,
      },
      process: {
        cpuPercent: current?.process.cpuPercent ?? 0,
        openFileDescriptors: current?.process.openFileDescriptors ?? 0,
        maxFileDescriptors: current?.process.maxFileDescriptors ?? 0,
      },
      dlq: {
        queueSizeBytes: current?.dlq?.queueSizeBytes ?? 0,
        maxQueueSizeBytes: current?.dlq?.maxQueueSizeBytes ?? 0,
        droppedEvents: current?.dlq?.droppedEvents ?? 0,
        expiredEvents: current?.dlq?.expiredEvents ?? 0,
      },
      logTypes: this.logTypeDeltas,
      config: this.pipelineConfig ?? {
        workers: 0,
        batchSize: 0,
        batchDelay: 0,
        queueType: "memory",
        dlqEnabled: false,
      },
    };
  }

  getHistory(
    range: "1h" | "6h" | "12h" | "24h" = "1h",
  ): MetricsDelta[] {
    const rangeMs = {
      "1h": 3600_000,
      "6h": 6 * 3600_000,
      "12h": 12 * 3600_000,
      "24h": 24 * 3600_000,
    }[range];
    const cutoff = Date.now() - rangeMs;
    return this.deltas.filter((d) => d.timestamp > cutoff);
  }

  getLatestSample(): MetricsSample | null {
    return this.latest;
  }

  getOutputPlugins(): PluginStat[] {
    return this.latest?.pipeline.plugins.outputs ?? [];
  }

  /** Return the raw circular buffer (cumulative samples) for support bundle export. */
  getBuffer(): MetricsSample[] {
    return [...this.buffer];
  }
}

function formatUptime(ms: number): string {
  const secs = Math.floor(ms / 1000);
  const days = Math.floor(secs / 86400);
  const hours = Math.floor((secs % 86400) / 3600);
  const mins = Math.floor((secs % 3600) / 60);

  if (days > 0) return `${days}d ${hours}h ${mins}m`;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

// Module-level singleton — starts polling on first import
export const metricsStore = new MetricsStore();
metricsStore.start();

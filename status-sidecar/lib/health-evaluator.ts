import { HealthResult, MetricsSample, MetricsDelta } from "./types";

const UNREACHABLE_THRESHOLD_MS = 30_000;
const STUCK_PIPELINE_THRESHOLD_MS = 5 * 60_000;

export function evaluateHealth(
  current: MetricsSample | null,
  recentDeltas: MetricsDelta[],
  lastContactMs: number,
  now: number,
): HealthResult {
  const reasons: string[] = [];

  // Unreachable check
  if (!current || now - lastContactMs > UNREACHABLE_THRESHOLD_MS) {
    return {
      status: "unhealthy",
      reasons: [
        `Logstash API unreachable for ${Math.round((now - lastContactMs) / 1000)}s`,
      ],
    };
  }

  // JVM heap check
  if (current.jvm.heapUsedPercent > 90) {
    reasons.push(
      `JVM heap at ${current.jvm.heapUsedPercent.toFixed(1)}% (>${90}%)`,
    );
  }

  // DLQ check
  if (current.dlq && current.dlq.queueSizeBytes > 0) {
    reasons.push(
      `Dead letter queue has ${formatBytes(current.dlq.queueSizeBytes)} of data`,
    );
  }

  // Output failures check
  const totalFailures = current.pipeline.plugins.outputs.reduce(
    (sum, p) => sum + (p.failures || 0),
    0,
  );
  if (totalFailures > 0) {
    reasons.push(`${totalFailures} output failures detected`);
  }

  // Pipeline stuck check: input > 0 but output = 0 for >5 minutes
  if (recentDeltas.length >= 5) {
    const window = recentDeltas.slice(-5);
    const totalWindowSecs = window.reduce(
      (s, d) => s + d.intervalSecs,
      0,
    );
    if (totalWindowSecs >= STUCK_PIPELINE_THRESHOLD_MS / 1000) {
      const hasInput = window.some((d) => d.inputEps > 0);
      const allOutputZero = window.every((d) => d.outputEps === 0);
      if (hasInput && allOutputZero) {
        reasons.push("Output EPS is 0 while input is active (pipeline stuck)");
      }
    }
  }

  if (reasons.length > 0) {
    return { status: "degraded", reasons };
  }

  return { status: "healthy", reasons: [] };
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

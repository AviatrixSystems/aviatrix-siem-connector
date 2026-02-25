import { readFile } from "fs/promises";
import { existsSync } from "fs";

const LOG_PATH =
  process.env.LOGSTASH_LOG_PATH ||
  "/var/log/logstash/logstash-plain.log";

/**
 * Fetch Logstash logs.
 *
 * Production: reads from LOGSTASH_LOG_PATH, a shared volume between the
 * Logstash container (--path.logs /var/log/logstash) and the sidecar.
 *
 * Development: if the file doesn't exist, falls back to `docker logs`
 * from LOGSTASH_CONTAINER env var or auto-detected container.
 *
 * Returns { content, source } on success, throws on failure.
 */
export async function getLogstashLogs(
  maxLines: number = 5000,
): Promise<{ content: string; source: string }> {
  // Primary: read from shared log file
  if (existsSync(LOG_PATH)) {
    const raw = await readFile(LOG_PATH, "utf-8");
    const lines = raw.split("\n");
    return {
      content: lines.slice(-maxLines).join("\n"),
      source: `file:${LOG_PATH}`,
    };
  }

  // Dev fallback: docker logs (lazy-load child_process)
  const result = tryDockerLogs(maxLines);
  if (result) return result;

  throw new Error(
    `No log source available.\n\n` +
      `Checked file: ${LOG_PATH} (not found)\n\n` +
      "Production setup:\n" +
      "  1. Start Logstash with: --path.logs /var/log/logstash\n" +
      "  2. Mount /var/log/logstash as a shared volume to both containers\n" +
      "  3. Set LOGSTASH_LOG_PATH if using a non-default path\n\n" +
      "Development: Set LOGSTASH_CONTAINER=<name> or ensure Docker CLI is available.",
  );
}

/**
 * Dev-only: try to fetch logs via `docker logs` command.
 * Returns null if Docker CLI is not available or no container found.
 */
function tryDockerLogs(
  maxLines: number,
): { content: string; source: string } | null {
  let execSync: typeof import("child_process").execSync;
  try {
    execSync = require("child_process").execSync;
  } catch {
    return null;
  }

  const containerName =
    process.env.LOGSTASH_CONTAINER || autoDetectContainer(execSync);
  if (!containerName) return null;

  try {
    const output = execSync(
      `docker logs --tail ${maxLines} ${containerName} 2>&1`,
      { timeout: 10_000, encoding: "utf-8" },
    );
    return { content: output, source: `docker:${containerName}` };
  } catch {
    return null;
  }
}

/**
 * Scan `docker ps` for a container with "logstash" in its image name.
 * Dev convenience only — not used in production.
 */
function autoDetectContainer(
  execSync: typeof import("child_process").execSync,
): string | null {
  try {
    const output = execSync(
      'docker ps --format "{{.ID}} {{.Image}} {{.Names}}" 2>/dev/null',
      { timeout: 5000, encoding: "utf-8" },
    );
    for (const line of output.trim().split("\n")) {
      if (line.toLowerCase().includes("logstash")) {
        const parts = line.split(/\s+/);
        return parts[parts.length - 1];
      }
    }
  } catch {
    // docker CLI not available
  }
  return null;
}

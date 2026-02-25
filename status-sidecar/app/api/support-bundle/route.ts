import { NextResponse } from "next/server";
import archiver from "archiver";
import { Readable } from "stream";
import { metricsStore } from "@/lib/metrics-store";
import { getHotThreads } from "@/lib/logstash-client";
import { getLogstashLogs } from "@/lib/logstash-logs";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const archive = archiver("tar", { gzip: true });
    const chunks: Buffer[] = [];

    // Collect archive data into buffer
    const promise = new Promise<Buffer>((resolve, reject) => {
      archive.on("data", (chunk: Buffer) => chunks.push(chunk));
      archive.on("end", () => resolve(Buffer.concat(chunks)));
      archive.on("error", reject);
    });

    // 1. Current stats snapshot (health, pipeline, JVM, log types, config)
    const stats = metricsStore.getStats();
    archive.append(JSON.stringify(stats, null, 2), {
      name: "stats.json",
    });

    // 2. Raw metrics buffer — cumulative samples with JVM, CPU, pipeline counters
    //    This always has useful data even when no events are flowing.
    const buffer = metricsStore.getBuffer();
    const samples = buffer.map((s) => ({
      timestamp: s.timestamp,
      time: new Date(s.timestamp).toISOString(),
      jvm: s.jvm,
      process: {
        cpuPercent: s.process.cpuPercent,
        openFileDescriptors: s.process.openFileDescriptors,
        maxFileDescriptors: s.process.maxFileDescriptors,
      },
      pipeline: {
        events: s.pipeline.events,
        queue: s.pipeline.queue,
        reloads: s.pipeline.reloads,
      },
      dlq: s.dlq,
    }));
    archive.append(JSON.stringify(samples, null, 2), {
      name: "samples.json",
    });

    // 3. Per-plugin stats from the latest sample — the raw plugin-level data
    //    Critical for diagnosing which specific plugins have issues.
    const latest = metricsStore.getLatestSample();
    if (latest) {
      const pluginStats = {
        timestamp: new Date(latest.timestamp).toISOString(),
        filters: latest.pipeline.plugins.filters,
        outputs: latest.pipeline.plugins.outputs,
      };
      archive.append(JSON.stringify(pluginStats, null, 2), {
        name: "plugin-stats.json",
      });
    }

    // 4. History deltas (rate-of-change between polls)
    for (const range of ["1h", "6h", "12h"] as const) {
      const history = metricsStore.getHistory(range);
      archive.append(JSON.stringify(history, null, 2), {
        name: `history-${range}.json`,
      });
    }

    // 5. Hot threads from Logstash
    try {
      const threads = await getHotThreads();
      archive.append(threads, { name: "hot-threads.txt" });
    } catch (e) {
      archive.append(
        `Failed to fetch hot threads from Logstash API.\nError: ${e}\n\nThis usually means Logstash is not reachable at ${process.env.LOGSTASH_API_URL ?? "http://localhost:9600"}.`,
        { name: "hot-threads.txt" },
      );
    }

    // 6. Logstash log file (from file or docker logs fallback)
    try {
      const { content: logContent, source } = await getLogstashLogs(5000);
      archive.append(`# Source: ${source}\n\n${logContent}`, {
        name: "logstash.log",
      });
    } catch (e) {
      archive.append(`${e instanceof Error ? e.message : e}`, {
        name: "logstash.log",
      });
    }

    // 7. Environment metadata
    const env: Record<string, string> = {
      timestamp: new Date().toISOString(),
      NODE_ENV: process.env.NODE_ENV ?? "",
      LOGSTASH_API_URL: process.env.LOGSTASH_API_URL ?? "http://localhost:9600",
      LOGSTASH_LOG_PATH: process.env.LOGSTASH_LOG_PATH ?? "/var/log/logstash/logstash-plain.log",
      LOG_PROFILE: process.env.LOG_PROFILE ?? "all",
      HOSTNAME: process.env.HOSTNAME ?? "",
      sidecarUptime: `${Math.floor((Date.now() - (buffer[0]?.timestamp ?? Date.now())) / 1000)}s`,
      logstashUptime: stats.uptime,
      logstashVersion: stats.version,
      bufferSamples: String(buffer.length),
    };
    archive.append(JSON.stringify(env, null, 2), {
      name: "environment.json",
    });

    archive.finalize();
    const archiveBuffer = await promise;

    const timestamp = new Date()
      .toISOString()
      .replace(/[:.]/g, "-")
      .slice(0, 19);

    // Convert Buffer to ReadableStream for NextResponse
    const stream = new ReadableStream({
      start(controller) {
        const readable = Readable.from(archiveBuffer);
        readable.on("data", (chunk) => controller.enqueue(chunk));
        readable.on("end", () => controller.close());
        readable.on("error", (err) => controller.error(err));
      },
    });

    return new NextResponse(stream, {
      headers: {
        "Content-Type": "application/gzip",
        "Content-Disposition": `attachment; filename="support-bundle-${timestamp}.tar.gz"`,
      },
    });
  } catch (err) {
    return NextResponse.json(
      { error: `Failed to generate support bundle: ${err}` },
      { status: 500 },
    );
  }
}

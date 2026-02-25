"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/ui/card";
import { Progress } from "@/ui/progress";
import { Caption } from "@/ui/typography";
import type { StatsSnapshot } from "@/lib/types";

interface ResourceHealthProps {
  stats: StatsSnapshot | null;
}

function progressState(percent: number): "success" | "paused" | "error" {
  if (percent > 90) return "error";
  if (percent > 70) return "paused";
  return "success";
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * 1024 * 1024)
    return `${(bytes / (1024 * 1024)).toFixed(0)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

export function ResourceHealth({ stats }: ResourceHealthProps) {
  const jvm = stats?.jvm;
  const proc = stats?.process;
  const dlq = stats?.dlq;

  const heapPercent = jvm?.heapUsedPercent ?? 0;
  const cpuPercent = proc?.cpuPercent ?? 0;
  const fdPercent =
    proc && proc.maxFileDescriptors > 0
      ? (proc.openFileDescriptors / proc.maxFileDescriptors) * 100
      : 0;

  return (
    <div className="grid grid-cols-2 gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle>JVM Heap</CardTitle>
        </CardHeader>
        <CardContent>
          <Progress
            value={heapPercent}
            state={progressState(heapPercent)}
            showStatus={false}
            showPercentage
          />
          <Caption className="mt-1.5 text-text-light">
            {formatBytes(jvm?.heapUsedBytes ?? 0)} /{" "}
            {formatBytes(jvm?.heapMaxBytes ?? 0)} &middot; GC:{" "}
            {(jvm?.gcCollectionCount ?? 0).toLocaleString()} collections,{" "}
            {((jvm?.gcCollectionTimeMs ?? 0) / 1000).toFixed(1)}s total
          </Caption>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle>CPU</CardTitle>
        </CardHeader>
        <CardContent>
          <Progress
            value={cpuPercent}
            state={progressState(cpuPercent)}
            showStatus={false}
            showPercentage
          />
          <Caption className="mt-1.5 text-text-light">
            Process CPU usage: {cpuPercent.toFixed(1)}%
          </Caption>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle>File Descriptors</CardTitle>
        </CardHeader>
        <CardContent>
          <Progress
            value={fdPercent}
            state={progressState(fdPercent)}
            showStatus={false}
            showPercentage
          />
          <Caption className="mt-1.5 text-text-light">
            {(proc?.openFileDescriptors ?? 0).toLocaleString()} /{" "}
            {(proc?.maxFileDescriptors ?? 0).toLocaleString()} open
          </Caption>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle>Dead Letter Queue</CardTitle>
        </CardHeader>
        <CardContent>
          {dlq && dlq.maxQueueSizeBytes > 0 ? (
            <>
              <Progress
                value={(dlq.queueSizeBytes / dlq.maxQueueSizeBytes) * 100}
                state={progressState(
                  (dlq.queueSizeBytes / dlq.maxQueueSizeBytes) * 100,
                )}
                showStatus={false}
                showPercentage
              />
              <Caption className="mt-1.5 text-text-light">
                {formatBytes(dlq.queueSizeBytes)} /{" "}
                {formatBytes(dlq.maxQueueSizeBytes)} &middot; Dropped:{" "}
                {dlq.droppedEvents.toLocaleString()} | Expired:{" "}
                {dlq.expiredEvents.toLocaleString()}
              </Caption>
            </>
          ) : (
            <>
              <Progress value={0} state="success" showStatus={false} showPercentage={false} />
              <Caption className="mt-1.5 text-text-light">
                No DLQ configured
              </Caption>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

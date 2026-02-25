"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/ui/card";
import { H3, Paragraph, Caption } from "@/ui/typography";
import type { StatsSnapshot } from "@/lib/types";

interface PipelineOverviewProps {
  stats: StatsSnapshot | null;
}

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return n.toLocaleString();
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

interface MetricCardProps {
  title: string;
  value: string;
  subtitle: string;
}

function MetricCard({ title, value, subtitle }: MetricCardProps) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle>
          <Caption className="text-text-medium">{title}</Caption>
        </CardTitle>
      </CardHeader>
      <CardContent>
        <H3>{value}</H3>
        <Paragraph className="text-text-light text-sm">{subtitle}</Paragraph>
      </CardContent>
    </Card>
  );
}

export function PipelineOverview({ stats }: PipelineOverviewProps) {
  const p = stats?.pipeline;

  return (
    <div className="grid grid-cols-4 gap-4">
      <MetricCard
        title="Events In"
        value={formatNumber(p?.eventsIn ?? 0)}
        subtitle={`${(p?.inputEps ?? 0).toFixed(1)} eps`}
      />
      <MetricCard
        title="Events Out"
        value={formatNumber(p?.eventsOut ?? 0)}
        subtitle={`${(p?.outputEps ?? 0).toFixed(1)} eps`}
      />
      <MetricCard
        title="Throughput"
        value={`${(p?.outputEps ?? 0).toFixed(1)} eps`}
        subtitle={`1h avg: ${(p?.avgEps1h ?? 0).toFixed(1)} eps`}
      />
      <MetricCard
        title="Queue"
        value={formatNumber(p?.queueEvents ?? 0)}
        subtitle={
          p?.queueMaxBytes
            ? `${formatBytes(p.queueSizeBytes)} / ${formatBytes(p.queueMaxBytes)}`
            : `${p?.queueType ?? "memory"} queue`
        }
      />
    </div>
  );
}

"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/ui/card";
import { Status } from "@/ui/status";
import type { StatsSnapshot } from "@/lib/types";

interface ConfigurationProps {
  stats: StatsSnapshot | null;
}

interface ConfigRow {
  label: string;
  value: React.ReactNode;
}

export function Configuration({ stats }: ConfigurationProps) {
  if (!stats) return null;

  const rows: ConfigRow[] = [
    { label: "Output Type", value: stats.outputType },
    { label: "Destination", value: stats.destination },
    { label: "Log Profile", value: stats.logProfile },
    { label: "Workers", value: stats.config.workers },
    { label: "Batch Size", value: stats.config.batchSize.toLocaleString() },
    { label: "Batch Delay", value: `${stats.config.batchDelay}ms` },
    { label: "Queue Type", value: stats.config.queueType },
    {
      label: "DLQ Enabled",
      value: stats.config.dlqEnabled ? (
        <Status state="success">Enabled</Status>
      ) : (
        <Status state="info">Disabled</Status>
      ),
    },
    {
      label: "Container ID",
      value: (
        <span className="font-mono text-xs">
          {process.env.HOSTNAME || "—"}
        </span>
      ),
    },
    { label: "Logstash Version", value: stats.version || "—" },
    { label: "Uptime", value: stats.uptime },
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Configuration</CardTitle>
      </CardHeader>
      <CardContent>
        <table className="w-full text-sm">
          <tbody>
            {rows.map((row) => (
              <tr key={row.label} className="border-b border-border-light">
                <td className="py-2 pr-4 font-semibold text-text-medium w-[180px]">
                  {row.label}
                </td>
                <td className="py-2">{row.value}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  );
}

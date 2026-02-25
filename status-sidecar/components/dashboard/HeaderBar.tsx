"use client";

import { CheckCircle, AlertTriangle, XCircle, HelpCircle } from "lucide-react";
import { Card, CardContent } from "@/ui/card";
import { H2, Paragraph, Caption } from "@/ui/typography";
import type { StatsSnapshot } from "@/lib/types";

interface HeaderBarProps {
  stats: StatsSnapshot | null;
}

function HealthIndicator({ status }: { status: string }) {
  switch (status) {
    case "healthy":
      return (
        <div className="flex items-center gap-1.5 text-success">
          <CheckCircle className="size-5" />
          <span className="text-sm font-semibold">Healthy</span>
        </div>
      );
    case "degraded":
      return (
        <div className="flex items-center gap-1.5 text-warning">
          <AlertTriangle className="size-5" />
          <span className="text-sm font-semibold">Degraded</span>
        </div>
      );
    case "unhealthy":
      return (
        <div className="flex items-center gap-1.5 text-error">
          <XCircle className="size-5" />
          <span className="text-sm font-semibold">Unhealthy</span>
        </div>
      );
    default:
      return (
        <div className="flex items-center gap-1.5 text-text-light">
          <HelpCircle className="size-5" />
          <span className="text-sm font-semibold">Unknown</span>
        </div>
      );
  }
}

export function HeaderBar({ stats }: HeaderBarProps) {
  return (
    <Card>
      <CardContent className="p-5">
        <H2>Aviatrix SIEM Connector</H2>

        {/* Status + metadata row */}
        <div className="mt-3 flex items-center gap-6 text-sm">
          <HealthIndicator status={stats?.health.status ?? "unknown"} />
          <div className="h-4 w-px bg-border-default" />
          <div className="flex items-center gap-1.5">
            <span className="text-text-light">Uptime:</span>
            <span className="font-semibold text-text-dark">{stats?.uptime ?? "—"}</span>
          </div>
          <div className="h-4 w-px bg-border-default" />
          <div className="flex items-center gap-2">
            <span className="text-text-light">Output:</span>
            <span className="font-medium text-text-dark">
              {stats?.outputType ?? "—"}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-text-light">Destination:</span>
            <span className="text-text-medium max-w-[400px] truncate">
              {stats?.destination ?? "—"}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-text-light">Profile:</span>
            <span className="font-medium text-text-dark">
              {stats?.logProfile ?? "—"}
            </span>
          </div>
          {stats?.version && (
            <div className="flex items-center gap-2">
              <span className="text-text-light">Version:</span>
              <span className="text-text-medium">v{stats.version}</span>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

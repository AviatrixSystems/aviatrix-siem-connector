"use client";

import { AppFrame } from "@/components/AppFrame";
import { useDashboardData } from "@/hooks/use-dashboard-data";
import { HeaderBar } from "@/components/dashboard/HeaderBar";
import { PipelineOverview } from "@/components/dashboard/PipelineOverview";
import { ThroughputChart } from "@/components/dashboard/ThroughputChart";
import { LogTypeBreakdown } from "@/components/dashboard/LogTypeBreakdown";
import { ResourceHealth } from "@/components/dashboard/ResourceHealth";
import { Configuration } from "@/components/dashboard/Configuration";
import { Actions } from "@/components/dashboard/Actions";
import { Divider } from "@/ui/divider";

export default function DashboardPage() {
  const { stats, history, isLoading, error, timeRange, setTimeRange } =
    useDashboardData();

  return (
    <AppFrame>
      <div className="flex flex-col gap-6 max-w-[1400px]">
        {/* Error banner */}
        {error && (
          <div className="rounded-sm bg-error-light p-3 text-sm text-error-dark">
            {error}
          </div>
        )}

        {/* Loading state */}
        {isLoading && !stats && (
          <div className="flex h-64 items-center justify-center text-text-medium">
            Connecting to Logstash...
          </div>
        )}

        {/* Actions at top */}
        <Actions />

        {/* Dashboard sections */}
        <HeaderBar stats={stats} />
        <PipelineOverview stats={stats} />
        <ThroughputChart
          history={history}
          timeRange={timeRange}
          onTimeRangeChange={setTimeRange}
        />
        <LogTypeBreakdown logTypes={stats?.logTypes ?? []} />
        <ResourceHealth stats={stats} />

        <Divider />

        <Configuration stats={stats} />
      </div>
    </AppFrame>
  );
}

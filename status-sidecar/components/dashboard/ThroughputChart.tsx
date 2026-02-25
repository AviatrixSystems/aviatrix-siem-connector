"use client";

import { useMemo } from "react";
import { useTheme } from "next-themes";
import { Card, CardContent, CardHeader, CardTitle } from "@/ui/card";
import { SegmentedButton } from "@/ui/segmented-button";
import { ChartWrapper } from "@/components/chart-wrapper";
import type { MetricsDelta } from "@/lib/types";

type TimeRange = "1h" | "6h" | "12h" | "24h";

interface ThroughputChartProps {
  history: MetricsDelta[];
  timeRange: string;
  onTimeRangeChange: (range: TimeRange) => void;
}

const TIME_RANGE_OPTIONS = [
  { value: "1h", label: "1h" },
  { value: "6h", label: "6h" },
  { value: "12h", label: "12h" },
  { value: "24h", label: "24h" },
];

export function ThroughputChart({
  history,
  timeRange,
  onTimeRangeChange,
}: ThroughputChartProps) {
  const { theme } = useTheme();

  const chartData = useMemo(() => {
    return history.map((d) => ({
      time: new Date(d.timestamp),
      inputEps: Math.round(d.inputEps * 100) / 100,
      outputEps: Math.round(d.outputEps * 100) / 100,
    }));
  }, [history]);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const options = useMemo((): any => {
    const isDark = theme === "dark";
    return {
      data: chartData,
      theme: isDark ? "ag-default-dark" : "ag-default",
      background: { fill: "transparent" },
      series: [
        {
          type: "bar" as const,
          xKey: "time",
          yKey: "inputEps",
          yName: "Input EPS",
          fill: "#6366f1",
          cornerRadius: 2,
        },
        {
          type: "bar" as const,
          xKey: "time",
          yKey: "outputEps",
          yName: "Output EPS",
          fill: "#22c55e",
          cornerRadius: 2,
        },
      ],
      axes: [
        {
          type: "time" as const,
          position: "bottom" as const,
          label: {
            format: timeRange === "1h" ? "%H:%M" : "%H:%M",
          },
        },
        {
          type: "number" as const,
          position: "left" as const,
          title: { text: "Events/sec" },
        },
      ],
      legend: {
        position: "bottom" as const,
      },
      height: 280,
    };
  }, [chartData, theme, timeRange]);

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle>Throughput</CardTitle>
        <SegmentedButton
          options={TIME_RANGE_OPTIONS}
          value={timeRange}
          onValueChange={(val) => onTimeRangeChange(String(val) as TimeRange)}
        />
      </CardHeader>
      <CardContent>
        {chartData.length > 0 ? (
          <ChartWrapper options={options} className="w-full" />
        ) : (
          <div className="flex h-[280px] items-center justify-center text-text-light">
            No data yet — metrics will appear after the first polling interval
          </div>
        )}
      </CardContent>
    </Card>
  );
}

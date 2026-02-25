"use client";

import dynamic from "next/dynamic";
import { ModuleRegistry, AllCommunityModule } from "ag-charts-community";

ModuleRegistry.registerModules(AllCommunityModule);

const AgCharts = dynamic(
  () => import("ag-charts-react").then((m) => m.AgCharts),
  { ssr: false },
);

interface ChartWrapperProps {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  options: any;
  className?: string;
}

export function ChartWrapper({ options, className }: ChartWrapperProps) {
  return (
    <div className={className}>
      <AgCharts options={options} />
    </div>
  );
}

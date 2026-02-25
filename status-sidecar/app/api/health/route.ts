import { NextResponse } from "next/server";
import { metricsStore } from "@/lib/metrics-store";

export const dynamic = "force-dynamic";

export function GET() {
  const health = metricsStore.getHealth();
  const status = health.status === "unhealthy" ? 503 : 200;

  return NextResponse.json(health, { status });
}

import { NextResponse } from "next/server";
import { metricsStore } from "@/lib/metrics-store";

export const dynamic = "force-dynamic";

export function GET() {
  const stats = metricsStore.getStats();
  return NextResponse.json(stats);
}

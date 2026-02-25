import { NextRequest, NextResponse } from "next/server";
import { metricsStore } from "@/lib/metrics-store";

export const dynamic = "force-dynamic";

export function GET(request: NextRequest) {
  const range = request.nextUrl.searchParams.get("range") || "1h";
  const validRanges = ["1h", "6h", "12h", "24h"] as const;

  if (!validRanges.includes(range as (typeof validRanges)[number])) {
    return NextResponse.json(
      { error: `Invalid range. Use: ${validRanges.join(", ")}` },
      { status: 400 },
    );
  }

  const history = metricsStore.getHistory(
    range as "1h" | "6h" | "12h" | "24h",
  );
  return NextResponse.json(history);
}

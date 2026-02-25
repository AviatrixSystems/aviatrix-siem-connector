import { NextRequest, NextResponse } from "next/server";
import { getLogstashLogs } from "@/lib/logstash-logs";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const download = request.nextUrl.searchParams.get("download") === "true";
  const linesParam = request.nextUrl.searchParams.get("lines");
  const maxLines = linesParam ? parseInt(linesParam, 10) : 1000;

  try {
    const { content } = await getLogstashLogs(maxLines);

    if (download) {
      return new NextResponse(content, {
        headers: {
          "Content-Type": "text/plain",
          "Content-Disposition": `attachment; filename="logstash-${new Date().toISOString().replace(/[:.]/g, "-")}.log"`,
        },
      });
    }

    return new NextResponse(content, {
      headers: { "Content-Type": "text/plain" },
    });
  } catch (err) {
    return NextResponse.json(
      { error: `${err instanceof Error ? err.message : err}` },
      { status: 404 },
    );
  }
}

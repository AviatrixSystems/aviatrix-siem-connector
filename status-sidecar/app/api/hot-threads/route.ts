import { NextResponse } from "next/server";
import { getHotThreads } from "@/lib/logstash-client";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const threads = await getHotThreads();
    return new NextResponse(threads, {
      headers: { "Content-Type": "text/plain" },
    });
  } catch (err) {
    return new NextResponse(
      `Failed to fetch hot threads: ${err}`,
      { status: 502, headers: { "Content-Type": "text/plain" } },
    );
  }
}

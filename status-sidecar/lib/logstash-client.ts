const BASE_URL = process.env.LOGSTASH_API_URL || "http://localhost:9600";
const TIMEOUT = 5000;

async function fetchWithTimeout(
  url: string,
  opts?: { responseType?: "json" | "text" },
): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      throw new Error(`Logstash API ${res.status}: ${res.statusText}`);
    }
    return opts?.responseType === "text" ? await res.text() : await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/* eslint-disable @typescript-eslint/no-explicit-any */
export async function getNodeStats(): Promise<any> {
  return fetchWithTimeout(`${BASE_URL}/_node/stats`);
}

export async function getNodeInfo(): Promise<any> {
  return fetchWithTimeout(`${BASE_URL}/_node`);
}

export async function getHotThreads(): Promise<string> {
  return fetchWithTimeout(`${BASE_URL}/_node/hot_threads?human=true`, {
    responseType: "text",
  }) as Promise<string>;
}
/* eslint-enable @typescript-eslint/no-explicit-any */

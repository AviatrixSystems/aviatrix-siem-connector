"use client";

import { useEffect, useState, useCallback } from "react";
import type { StatsSnapshot, MetricsDelta } from "@/lib/types";

type TimeRange = "1h" | "6h" | "12h" | "24h";

interface DashboardData {
  stats: StatsSnapshot | null;
  history: MetricsDelta[];
  isLoading: boolean;
  error: string | null;
  timeRange: TimeRange;
  setTimeRange: (range: TimeRange) => void;
}

export function useDashboardData(): DashboardData {
  const [stats, setStats] = useState<StatsSnapshot | null>(null);
  const [history, setHistory] = useState<MetricsDelta[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [timeRange, setTimeRange] = useState<TimeRange>("1h");

  const fetchStats = useCallback(async () => {
    try {
      const res = await fetch("/api/stats");
      if (!res.ok) throw new Error(`Stats API ${res.status}`);
      const data = await res.json();
      setStats(data);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to fetch stats");
    } finally {
      setIsLoading(false);
    }
  }, []);

  const fetchHistory = useCallback(async () => {
    try {
      const res = await fetch(`/api/history?range=${timeRange}`);
      if (!res.ok) throw new Error(`History API ${res.status}`);
      const data = await res.json();
      setHistory(data);
    } catch {
      // Non-critical — chart just won't update
    }
  }, [timeRange]);

  // Poll stats every 10s
  useEffect(() => {
    fetchStats();
    const interval = setInterval(fetchStats, 10_000);
    return () => clearInterval(interval);
  }, [fetchStats]);

  // Fetch history on time range change and periodically
  useEffect(() => {
    fetchHistory();
    const interval = setInterval(fetchHistory, 60_000);
    return () => clearInterval(interval);
  }, [fetchHistory]);

  return { stats, history, isLoading, error, timeRange, setTimeRange };
}

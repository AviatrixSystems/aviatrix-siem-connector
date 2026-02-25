"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/ui/card";
import { LOG_TYPE_LABELS } from "@/lib/types";
import type { LogTypeDelta } from "@/lib/types";

interface LogTypeBreakdownProps {
  logTypes: LogTypeDelta[];
}

function rowColor(row: LogTypeDelta): string {
  if (row.failed > 0) return "text-error";
  if (row.received > 0 && row.sent === 0) return "text-error";
  if (row.dropped > 0) return "text-warning";
  return "";
}

export function LogTypeBreakdown({ logTypes }: LogTypeBreakdownProps) {
  const totals = logTypes.reduce(
    (acc, lt) => ({
      received: acc.received + lt.received,
      dropped: acc.dropped + lt.dropped,
      sent: acc.sent + lt.sent,
      failed: acc.failed + lt.failed,
      eps: acc.eps + lt.eps,
    }),
    { received: 0, dropped: 0, sent: 0, failed: 0, eps: 0 },
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Log Type Breakdown</CardTitle>
      </CardHeader>
      <CardContent>
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border-default text-left text-text-medium">
              <th className="pb-2 font-semibold">Log Type</th>
              <th className="pb-2 text-right font-semibold">Received</th>
              <th className="pb-2 text-right font-semibold">Dropped</th>
              <th className="pb-2 pl-3 font-semibold">Reason</th>
              <th className="pb-2 text-right font-semibold">Sent</th>
              <th className="pb-2 text-right font-semibold">Failed</th>
              <th className="pb-2 text-right font-semibold">EPS</th>
            </tr>
          </thead>
          <tbody>
            {logTypes.map((lt) => (
              <tr
                key={lt.logType}
                className={`border-b border-border-light ${rowColor(lt)}`}
              >
                <td className="py-2">
                  {LOG_TYPE_LABELS[lt.logType]}
                </td>
                <td className="py-2 text-right">{lt.received.toLocaleString()}</td>
                <td className="py-2 text-right">{lt.dropped.toLocaleString()}</td>
                <td className="py-2 pl-3 text-xs text-text-light">
                  {lt.dropReasons.length > 0
                    ? lt.dropReasons
                        .map((r) => `${r.count} ${r.reason.toLowerCase()}`)
                        .join(", ")
                    : ""}
                </td>
                <td className="py-2 text-right">{lt.sent.toLocaleString()}</td>
                <td className="py-2 text-right">{lt.failed.toLocaleString()}</td>
                <td className="py-2 text-right">{lt.eps.toFixed(1)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="font-semibold">
              <td className="pt-2">Total</td>
              <td className="pt-2 text-right">{totals.received.toLocaleString()}</td>
              <td className="pt-2 text-right">{totals.dropped.toLocaleString()}</td>
              <td className="pt-2"></td>
              <td className="pt-2 text-right">{totals.sent.toLocaleString()}</td>
              <td className="pt-2 text-right">{totals.failed.toLocaleString()}</td>
              <td className="pt-2 text-right">{totals.eps.toFixed(1)}</td>
            </tr>
          </tfoot>
        </table>
      </CardContent>
    </Card>
  );
}

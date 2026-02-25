"use client";

import { HeartPulse } from "lucide-react";
import { H5 } from "@/ui/typography";

export function AppNav() {
  return (
    <nav
      className="flex flex-col h-full w-[220px] shrink-0"
      style={{ backgroundColor: "rgba(35,29,48,1)" }}
    >
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-4">
        <H5 className="text-text-default-inverse">Aviatrix</H5>
      </div>

      {/* Active nav item */}
      <div
        className="flex h-10 w-full items-center gap-2 px-4 cursor-pointer"
        style={{ backgroundColor: "rgba(90,77,122,1)" }}
      >
        <HeartPulse className="size-5 text-white" />
        <span className="text-sm text-white">Dashboard</span>
      </div>
    </nav>
  );
}

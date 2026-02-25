"use client";

import { useState, useEffect } from "react";
import { Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { IconButtonLite } from "@/ui/icon-button-lite";
import { Paragraph } from "@/ui/typography";
import { AppNav } from "./AppNav";

export function AppFrame({ children }: { children: React.ReactNode }) {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  return (
    <div className="flex h-screen overflow-hidden">
      <AppNav />

      <div className="flex flex-1 flex-col overflow-hidden">
        {/* Top header bar */}
        <header className="flex h-12 shrink-0 items-center justify-between border-b border-border-default px-4">
          <Paragraph className="font-semibold">Service Monitor</Paragraph>
          {mounted && (
            <IconButtonLite
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              aria-label="Toggle theme"
            >
              {theme === "dark" ? (
                <Sun className="size-icon-md" />
              ) : (
                <Moon className="size-icon-md" />
              )}
            </IconButtonLite>
          )}
        </header>

        {/* Scrollable content */}
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}

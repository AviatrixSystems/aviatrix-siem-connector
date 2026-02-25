"use client";

import { ThemeProvider } from "next-themes";
import { TooltipProvider } from "@/ui/tooltip";
import { Toaster } from "@/ui/toast";

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <ThemeProvider attribute="class" defaultTheme="dark" enableSystem={false}>
      <TooltipProvider>
        {children}
        <Toaster />
      </TooltipProvider>
    </ThemeProvider>
  );
}

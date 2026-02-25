"use client";

import { useState } from "react";
import { Download, FileArchive, Cpu } from "lucide-react";
import { Button } from "@/ui/button";
import { HotThreadsDialog } from "./HotThreadsDialog";

export function Actions() {
  const [hotThreadsOpen, setHotThreadsOpen] = useState(false);

  return (
    <>
      <div className="flex gap-3">
        <Button
          intent="secondary"
          onClick={() => {
            window.location.href = "/api/logs?download=true";
          }}
        >
          <Download className="size-icon-md mr-2" />
          Download Logs
        </Button>
        <Button
          intent="secondary"
          onClick={() => {
            window.location.href = "/api/support-bundle";
          }}
        >
          <FileArchive className="size-icon-md mr-2" />
          Support Bundle
        </Button>
        <Button intent="secondary" onClick={() => setHotThreadsOpen(true)}>
          <Cpu className="size-icon-md mr-2" />
          Hot Threads
        </Button>
      </div>

      <HotThreadsDialog
        open={hotThreadsOpen}
        onOpenChange={setHotThreadsOpen}
      />
    </>
  );
}

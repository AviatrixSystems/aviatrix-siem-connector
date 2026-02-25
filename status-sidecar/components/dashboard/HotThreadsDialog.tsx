"use client";

import { useState, useEffect } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogBody,
} from "@/ui/dialog";

interface HotThreadsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function HotThreadsDialog({ open, onOpenChange }: HotThreadsDialogProps) {
  const [content, setContent] = useState<string>("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    fetch("/api/hot-threads")
      .then((res) => res.text())
      .then((text) => setContent(text))
      .catch((err) => setContent(`Error: ${err.message}`))
      .finally(() => setLoading(false));
  }, [open]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[80vh]">
        <DialogHeader>
          <DialogTitle>Hot Threads</DialogTitle>
        </DialogHeader>
        <DialogBody className="overflow-auto">
          {loading ? (
            <div className="py-8 text-center text-text-medium">
              Loading hot threads...
            </div>
          ) : (
            <pre className="whitespace-pre-wrap font-mono text-xs leading-relaxed bg-background-dark p-4 rounded-sm overflow-auto max-h-[60vh]">
              {content || "No data"}
            </pre>
          )}
        </DialogBody>
      </DialogContent>
    </Dialog>
  );
}

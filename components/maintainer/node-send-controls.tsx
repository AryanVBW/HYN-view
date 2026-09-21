"use client";

import { useState, useTransition } from "react";
import { BellRing, FileText, Loader2 } from "lucide-react";
import {
  sendMaintainerNodeNotification,
  sendMaintainerNodeReport,
  type MaintainerSendResult,
} from "@/app/maintainer/actions";

const button =
  "inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-mono text-xs uppercase transition-colors disabled:opacity-40";

export function NodeSendControls({ nodeId, nodeName }: { nodeId: string; nodeName: string }) {
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<MaintainerSendResult | null>(null);
  const [busy, setBusy] = useState<"notification" | "report" | null>(null);

  function send(kind: "notification" | "report") {
    setResult(null);
    setBusy(kind);
    startTransition(async () => {
      try {
        const outcome = kind === "report"
          ? await sendMaintainerNodeReport(nodeId)
          : await sendMaintainerNodeNotification(nodeId);
        setResult(outcome);
      } catch {
        setResult({ ok: false, error: "The request failed. Nothing was confirmed as sent." });
      } finally {
        setBusy(null);
      }
    });
  }

  return (
    <div className="flex flex-col items-start gap-2">
      <div className="flex flex-wrap items-center gap-1.5">
        <button
          type="button"
          disabled={pending}
          onClick={() => send("notification")}
          aria-label={`Send a notification for ${nodeName}`}
          className={`${button} border-border text-muted-foreground hover:border-primary/60 hover:text-primary`}
        >
          {busy === "notification" ? <Loader2 className="size-3 animate-spin" /> : <BellRing className="size-3" />}
          notify
        </button>
        <button
          type="button"
          disabled={pending}
          onClick={() => send("report")}
          aria-label={`Send a report for ${nodeName}`}
          className={`${button} border-border text-muted-foreground hover:border-primary/60 hover:text-primary`}
        >
          {busy === "report" ? <Loader2 className="size-3 animate-spin" /> : <FileText className="size-3" />}
          report
        </button>
      </div>
      {result ? (
        <p
          role={result.ok ? "status" : "alert"}
          className={`font-mono text-[0.65rem] leading-5 ${result.ok ? "text-primary" : "text-destructive"}`}
        >
          {result.ok ? result.message : result.error}
        </p>
      ) : null}
    </div>
  );
}

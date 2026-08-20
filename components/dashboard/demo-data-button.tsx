"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { FlaskConical, Loader2, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

// Demo data is strictly opt-in and always labelled. It exists so the dashboard
// can be evaluated without a paired server; it must never be mistaken for
// telemetry from a real machine, which is why the seeded node is flagged
// is_demo in the database and badged everywhere it appears in the UI.
export function DemoDataButton({
  mode,
  className = "",
}: {
  mode: "seed" | "clear";
  className?: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run() {
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc(mode === "seed" ? "hyn_demo_seed" : "hyn_demo_clear");
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    router.refresh();
  }

  return (
    <div className={className}>
      <Button type="button" size="sm" onClick={run} disabled={busy} className="gap-2">
        {busy ? (
          <Loader2 className="size-4 animate-spin" />
        ) : mode === "seed" ? (
          <FlaskConical className="size-4" />
        ) : (
          <Trash2 className="size-4" />
        )}
        {mode === "seed" ? "Load demo data" : "Remove demo data"}
      </Button>
      {error ? (
        <p role="alert" className="mt-2 font-mono text-xs text-destructive">
          {error}
        </p>
      ) : null}
    </div>
  );
}

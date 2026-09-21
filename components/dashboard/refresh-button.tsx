"use client";

import { useTransition } from "react";
import { Loader2, RefreshCw } from "lucide-react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

// Re-runs the server component in place instead of a full page reload, so a
// profile row that just became visible resolves without losing scroll state.
export function RefreshButton() {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  return (
    <Button
      size="sm"
      disabled={pending}
      onClick={() => startTransition(() => router.refresh())}
      className="gap-2"
    >
      {pending ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
      Refresh
    </Button>
  );
}

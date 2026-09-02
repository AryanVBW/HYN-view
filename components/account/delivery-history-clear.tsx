"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Eraser, Loader2, RotateCcw } from "lucide-react";
import { DELIVERY_CLEARED_COOKIE, DELIVERY_CLEARED_MAX_AGE } from "@/lib/delivery-history";

// Clearing the delivery history is a view control, not a delete: nothing here
// touches notification_log, so the records stay for the administrator's
// fleet-wide log and for the 30-day counters on this page, and the same person can
// put their own view back. That is why the control is undoable and says so --
// a button that looked like it deleted a year of delivery evidence, and did not,
// would be worse than either honest option.
//
// The cutoff is written to a cookie and the server component re-renders from it
// (see lib/delivery-history.ts), so the rows are filtered before they are sent
// rather than painted and then hidden.
export function ClearDeliveryHistoryButton({
  latestTs,
  cleared,
}: {
  latestTs?: string;
  cleared: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function write(value: string | null) {
    document.cookie = value
      ? `${DELIVERY_CLEARED_COOKIE}=${encodeURIComponent(value)}; path=/; max-age=${DELIVERY_CLEARED_MAX_AGE}; SameSite=Lax`
      : `${DELIVERY_CLEARED_COOKIE}=; path=/; max-age=0; SameSite=Lax`;
    startTransition(() => router.refresh());
  }

  const icon = pending ? (
    <Loader2 className="size-3 animate-spin" aria-hidden />
  ) : cleared ? (
    <RotateCcw className="size-3" aria-hidden />
  ) : (
    <Eraser className="size-3" aria-hidden />
  );

  return (
    <div className="flex flex-wrap items-center gap-2">
      {cleared ? (
        <button
          type="button"
          onClick={() => write(null)}
          disabled={pending}
          className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 font-mono text-[0.7rem] uppercase text-muted-foreground transition-colors hover:border-foreground/40 hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50"
        >
          {icon}
          show all again
        </button>
      ) : null}
      {latestTs ? (
        <button
          type="button"
          onClick={() => write(latestTs)}
          disabled={pending}
          title="Hide these from your view. Nothing is deleted."
          className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 font-mono text-[0.7rem] uppercase text-muted-foreground transition-colors hover:border-foreground/40 hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50"
        >
          {cleared ? <Eraser className="size-3" aria-hidden /> : icon}
          clear
        </button>
      ) : null}
    </div>
  );
}

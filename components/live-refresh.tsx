"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { startRecurringRefresh } from "@/lib/live-refresh";

export function LiveRefresh() {
  const router = useRouter();
  useEffect(() => startRecurringRefresh(() => router.refresh()), [router]);
  return null;
}

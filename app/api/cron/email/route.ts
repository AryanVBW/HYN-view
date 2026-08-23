import { NextResponse } from "next/server";
import { dispatchScheduledEmails } from "@/lib/scheduled-email";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

export async function GET(request: Request) {
  const cronSecret = process.env.CRON_SECRET ?? "";
  if (!cronSecret || request.headers.get("authorization") !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ message: "unauthorized" }, { status: 401 });
  }
  try {
    const result = await dispatchScheduledEmails();
    return NextResponse.json({ status: "ok", ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "scheduled email dispatch failed";
    return NextResponse.json(
      { message },
      { status: /not configured/i.test(message) ? 503 : 500 },
    );
  }
}

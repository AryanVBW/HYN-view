import { NextResponse } from "next/server";
import { pruneTelemetry } from "@/lib/telemetry-retention";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({message: "unauthorized"}, {status: 401});
  }
  try {
    return NextResponse.json(await pruneTelemetry(), {headers: {"Cache-Control": "no-store"}});
  } catch {
    return NextResponse.json({message: "Telemetry maintenance unavailable"}, {status: 503});
  }
}

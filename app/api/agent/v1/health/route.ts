import { NextResponse } from "next/server";

// No auth, database call or background job. Used only on endpoint discovery.
export function GET() {
  return NextResponse.json({ service: "hyn-agent-v1", transient_snapshots: true }, {
    headers: { "Cache-Control": "public, max-age=300" },
  });
}

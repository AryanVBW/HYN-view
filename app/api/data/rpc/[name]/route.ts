import { NextResponse } from "next/server";
import { isD1Data, userDataRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  context: { params: Promise<{ name: string }> },
) {
  const { name } = await context.params;
  if (!/^[a-z0-9_]{3,80}$/.test(name)) {
    return NextResponse.json({ message: "unknown rpc" }, { status: 404 });
  }
  let args: Record<string, unknown> = {};
  try {
    const body = await request.json();
    if (body && typeof body === "object" && !Array.isArray(body)) args = body as Record<string, unknown>;
  } catch {
    args = {};
  }
  if (isD1Data()) {
    const result = await userDataRpc(name, args);
    if (result.error) {
      const status = /not authenticated|sign in/i.test(result.error.message) ? 401 : 400;
      return NextResponse.json({ message: result.error.message }, { status });
    }
    return NextResponse.json(result.data, { headers: { "Cache-Control": "private, no-store" } });
  }
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(name, args);
  if (error) return NextResponse.json({ message: error.message }, { status: 400 });
  return NextResponse.json(data, { headers: { "Cache-Control": "private, no-store" } });
}

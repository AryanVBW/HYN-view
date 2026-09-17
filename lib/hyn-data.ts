import { createClient } from "@/lib/supabase/server";

export function dataApiUrl(): string {
  return (process.env.HYN_DATA_API_URL ?? "").replace(/\/$/, "");
}

export function isD1Data(): boolean {
  return dataApiUrl().length > 0;
}

type RpcResult<T> = { data: T | null; error: { message: string; code?: string } | null };

async function parse(res: Response): Promise<RpcResult<unknown>> {
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    const message = body && typeof body === "object" && "message" in body
      ? String((body as { message: unknown }).message)
      : res.statusText || "data request failed";
    return { data: null, error: { message } };
  }
  return { data: body, error: null };
}

export async function dataRpc<T>(name: string, args: Record<string, unknown> = {}, token?: string): Promise<RpcResult<T>> {
  const base = dataApiUrl();
  if (!base) return { data: null, error: { message: "HYN_DATA_API_URL is not configured" } };
  const auth = token ?? process.env.HYN_DATA_SERVICE_KEY ?? "";
  if (!auth) return { data: null, error: { message: "missing data credentials" } };
  const res = await fetch(`${base}/rpc/${encodeURIComponent(name)}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${auth}`,
    },
    body: JSON.stringify(args),
    cache: "no-store",
  });
  return parse(res) as Promise<RpcResult<T>>;
}

export async function userDataToken(): Promise<{ token: string; userId: string | null }> {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return { token: "", userId: null };
  const { data: session } = await supabase.auth.getSession();
  return { token: session.session?.access_token ?? "", userId: auth.user.id };
}

export async function userDataRpc<T>(name: string, args: Record<string, unknown> = {}): Promise<RpcResult<T>> {
  const { token } = await userDataToken();
  if (!token) return { data: null, error: { message: "Sign in required" } };
  return dataRpc<T>(name, args, token);
}

export async function storeRpc<T>(name: string, args: Record<string, unknown> = {}): Promise<RpcResult<T>> {
  if (isD1Data()) return userDataRpc<T>(name, args);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(name, args);
  return {
    data: (data as T) ?? null,
    error: error ? { message: error.message, code: error.code } : null,
  };
}

export async function proxyAgent(action: string, request: Request): Promise<Response> {
  const base = dataApiUrl();
  const raw = await request.arrayBuffer();
  const headers = new Headers();
  const contentType = request.headers.get("content-type");
  if (contentType) headers.set("content-type", contentType);
  const forwarded = request.headers.get("x-forwarded-for") ?? request.headers.get("x-real-ip");
  if (forwarded) headers.set("x-forwarded-for", forwarded);
  const res = await fetch(`${base}/api/agent/v1/${encodeURIComponent(action)}`, {
    method: "POST",
    headers,
    body: raw,
  });
  return new Response(res.body, {
    status: res.status,
    headers: { "content-type": res.headers.get("content-type") ?? "application/json", "cache-control": "no-store" },
  });
}

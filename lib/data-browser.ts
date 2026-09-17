export async function portalRpc<T>(name: string, args: Record<string, unknown> = {}): Promise<{
  data: T | null;
  error: { message: string } | null;
}> {
  const res = await fetch(`/api/data/rpc/${encodeURIComponent(name)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(args),
    cache: "no-store",
  });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    const message = body && typeof body === "object" && "message" in body
      ? String((body as { message: unknown }).message)
      : "request failed";
    return { data: null, error: { message } };
  }
  return { data: body as T, error: null };
}

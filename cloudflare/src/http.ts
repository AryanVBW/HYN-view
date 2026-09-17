export class RpcError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

export function json(data: unknown, status = 200): Response {
  return Response.json(data, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

export function jsonMessage(message: string, status: number): Response {
  return json({ message }, status);
}

export async function readJsonObject(request: Request, maxBytes: number): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > maxBytes) throw new RpcError("agent request exceeds 1 MB", 413);
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > maxBytes) throw new RpcError("agent request exceeds 1 MB", 413);
  let body: unknown;
  try {
    body = JSON.parse(raw || "{}");
  } catch {
    throw new RpcError("request body must be valid JSON");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new RpcError("request body must be a JSON object");
  }
  return body as Record<string, unknown>;
}

export function bearer(request: Request): string | null {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)/i.exec(header);
  return match?.[1] ?? null;
}

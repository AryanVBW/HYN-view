const DEFAULT_ORIGIN = "https://www.hyn-view.in";

// Heroku terminates TLS before forwarding to the Next server. request.url can
// therefore contain 0.0.0.0:PORT. Use a verified public host for redirects, never
// an arbitrary Host/X-Forwarded-Host supplied by a caller.
export function portalOrigin(
  request: Pick<Request, "url" | "headers">,
  configured = process.env.NEXT_PUBLIC_SITE_URL ?? DEFAULT_ORIGIN,
) {
  let canonical = DEFAULT_ORIGIN;
  try { canonical = new URL(configured).origin; } catch { /* use hosted default */ }
  const allowed = new Set([DEFAULT_ORIGIN, "https://hyn-view.in", canonical]);
  for (const header of ["host", "x-forwarded-host"]) {
    const host = request.headers.get(header)?.split(",", 1)[0]?.trim();
    if (!host || /[/@\\\s]/.test(host)) continue;
    try {
      const origin = new URL(`https://${host}`).origin;
      if (allowed.has(origin)) return origin;
    } catch { /* reject invalid host */ }
  }
  if (process.env.NODE_ENV !== "production") {
    const local = new URL(request.url);
    if (["localhost", "127.0.0.1", "[::1]"].includes(local.hostname)) return local.origin;
  }
  return canonical;
}

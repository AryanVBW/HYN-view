const enc = new TextEncoder();

function b64urlToBytes(value: string): Uint8Array {
  const b64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(padded);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export type JwtUser = {
  id: string;
  email: string | null;
};

export type JwtVerifyOptions = {
  secret?: string;
  issuer?: string;
  jwksUrl?: string;
  jwks?: JsonWebKey[];
};

type JwtHeader = { alg?: string; kid?: string; typ?: string };

const jwksCache = new Map<string, { exp: number; keys: JsonWebKey[] }>();

async function loadJwks(options: JwtVerifyOptions): Promise<JsonWebKey[]> {
  if (options.jwks?.length) return options.jwks;
  const url = options.jwksUrl;
  if (!url) throw new Error("not authenticated");
  const cached = jwksCache.get(url);
  if (cached && cached.exp > Date.now()) return cached.keys;
  const res = await fetch(url, { headers: { accept: "application/json" } });
  if (!res.ok) throw new Error("not authenticated");
  const body = await res.json() as { keys?: JsonWebKey[] };
  const keys = Array.isArray(body.keys) ? body.keys : [];
  if (!keys.length) throw new Error("not authenticated");
  jwksCache.set(url, { exp: Date.now() + 5 * 60_000, keys });
  return keys;
}

async function verifyHs256(data: Uint8Array, signature: Uint8Array, secret: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify("HMAC", key, signature, data);
}

async function verifyEs256(
  data: Uint8Array,
  signature: Uint8Array,
  header: JwtHeader,
  options: JwtVerifyOptions,
): Promise<boolean> {
  const keys = await loadJwks(options);
  const jwk = (header.kid ? keys.find((key) => (key as { kid?: string }).kid === header.kid) : keys[0]) ?? keys[0];
  if (!jwk) return false;
  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature, data);
}

export async function verifySupabaseJwt(
  token: string,
  secretOrOptions: string | JwtVerifyOptions,
  issuer?: string,
): Promise<JwtUser> {
  const options: JwtVerifyOptions = typeof secretOrOptions === "string"
    ? { secret: secretOrOptions, issuer }
    : secretOrOptions;
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("not authenticated");
  const [headerB64, payloadB64, sigB64] = parts as [string, string, string];
  let header: JwtHeader;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlToBytes(headerB64))) as JwtHeader;
  } catch {
    throw new Error("not authenticated");
  }
  const data = enc.encode(`${headerB64}.${payloadB64}`);
  const signature = b64urlToBytes(sigB64);
  let ok = false;
  if (header.alg === "HS256") {
    if (!options.secret) throw new Error("not authenticated");
    ok = await verifyHs256(data, signature, options.secret);
  } else if (header.alg === "ES256") {
    ok = await verifyEs256(data, signature, header, options);
  }
  if (!ok) throw new Error("not authenticated");
  let payload: { sub?: unknown; email?: unknown; exp?: unknown; iss?: unknown };
  try {
    payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(payloadB64))) as typeof payload;
  } catch {
    throw new Error("not authenticated");
  }
  if (typeof payload.sub !== "string" || !payload.sub) throw new Error("not authenticated");
  if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) {
    throw new Error("not authenticated");
  }
  if (options.issuer && typeof payload.iss === "string" && payload.iss !== options.issuer) {
    throw new Error("not authenticated");
  }
  return {
    id: payload.sub,
    email: typeof payload.email === "string" ? payload.email : null,
  };
}

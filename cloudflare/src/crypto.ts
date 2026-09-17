const enc = new TextEncoder();

export function nowIso(date = new Date()): string {
  return date.toISOString();
}

export function hoursAgoIso(hours: number, date = new Date()): string {
  return new Date(date.getTime() - hours * 3600_000).toISOString();
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hmacSha256Hex(value: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(value));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function equalHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function randomHex(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return [...buf].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function uuid(): string {
  return crypto.randomUUID();
}

const USER_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ";

export function userCode(): string {
  const out: string[] = [];
  while (out.length < 8) {
    const buf = new Uint8Array(16);
    crypto.getRandomValues(buf);
    for (const v of buf) {
      if (v >= 240) continue;
      out.push(USER_CODE_ALPHABET[v % 30]!);
      if (out.length === 8) break;
    }
  }
  return `${out.slice(0, 4).join("")}-${out.slice(4).join("")}`;
}

export function normalizeUserCode(raw: string): string {
  const bare = raw.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
  if (bare.length !== 8) return bare;
  return `${bare.slice(0, 4)}-${bare.slice(4)}`;
}

export async function userCodeHash(code: string, pepper: string): Promise<string> {
  return hmacSha256Hex(normalizeUserCode(code), pepper);
}

export function utf8Bytes(value: string): number {
  return enc.encode(value).length;
}

export function jsonBytes(value: unknown): number {
  return utf8Bytes(JSON.stringify(value));
}

export function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

export function asString(value: unknown, max = 10_000): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, max);
}

export function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export function path(obj: Record<string, unknown> | null, keys: string[]): unknown {
  let cur: unknown = obj;
  for (const key of keys) {
    const rec = asRecord(cur);
    if (!rec) return null;
    cur = rec[key];
  }
  return cur;
}

export function nestNum(obj: Record<string, unknown> | null, keys: string[]): number | null {
  return asFiniteNumber(path(obj, keys));
}

export function nestStr(obj: Record<string, unknown> | null, keys: string[], max = 200): string | null {
  const v = path(obj, keys);
  return typeof v === "string" ? v.slice(0, max) || null : null;
}

export function parseIso(value: unknown, fallback: string): string | null {
  if (value == null || value === "") return fallback;
  if (typeof value !== "string" && typeof value !== "number") return null;
  const d = new Date(value);
  if (!Number.isFinite(d.getTime())) return null;
  return d.toISOString();
}

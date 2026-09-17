import assert from "node:assert/strict";
import { test } from "node:test";
import { verifySupabaseJwt } from "../src/jwt.ts";

async function sign(payload: Record<string, unknown>, secret: string) {
  const enc = new TextEncoder();
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(`${header}.${body}`));
  const signature = Buffer.from(sig).toString("base64url");
  return `${header}.${body}.${signature}`;
}

test("accepts a live HS256 supabase-style token", async () => {
  const token = await sign({ sub: "user-1", email: "a@example.com", exp: Math.floor(Date.now() / 1000) + 60 }, "secret");
  const user = await verifySupabaseJwt(token, "secret");
  assert.equal(user.id, "user-1");
  assert.equal(user.email, "a@example.com");
});

test("rejects a bad signature", async () => {
  const token = await sign({ sub: "user-1", exp: Math.floor(Date.now() / 1000) + 60 }, "secret");
  await assert.rejects(() => verifySupabaseJwt(token, "other"), /not authenticated/);
});

test("accepts an ES256 supabase-style token against JWKS", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey) as JsonWebKey;
  jwk.kid = "test-es256";
  jwk.alg = "ES256";
  jwk.use = "sig";
  const header = Buffer.from(JSON.stringify({ alg: "ES256", typ: "JWT", kid: "test-es256" })).toString("base64url");
  const body = Buffer.from(JSON.stringify({
    sub: "user-es",
    email: "es@example.com",
    exp: Math.floor(Date.now() / 1000) + 60,
    iss: "https://example.supabase.co/auth/v1",
  })).toString("base64url");
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    pair.privateKey,
    new TextEncoder().encode(`${header}.${body}`),
  );
  const token = `${header}.${body}.${Buffer.from(sig).toString("base64url")}`;
  const user = await verifySupabaseJwt(token, {
    issuer: "https://example.supabase.co/auth/v1",
    jwks: [jwk],
  });
  assert.equal(user.id, "user-es");
  assert.equal(user.email, "es@example.com");
});

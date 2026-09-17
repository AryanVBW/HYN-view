import { ensureProfile } from "./access.ts";
import { bearer, RpcError } from "./http.ts";
import { verifySupabaseJwt } from "./jwt.ts";
import type { Session } from "./types.ts";

const USER_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function jwksUrl(env: Env): string | undefined {
  const base = (env.SUPABASE_URL ?? "").replace(/\/$/, "");
  return base ? `${base}/auth/v1/.well-known/jwks.json` : undefined;
}

function serviceSession(): Session {
  return {
    userId: "service",
    email: null,
    service: true,
    profile: {
      id: "service",
      email: null,
      full_name: null,
      role: "super_admin",
      status: "active",
      suspended_reason: null,
      created_at: new Date(0).toISOString(),
      updated_at: new Date(0).toISOString(),
    },
  };
}

export async function sessionFromRequest(request: Request, env: Env): Promise<Session> {
  const token = bearer(request);
  if (!token) throw new RpcError("not authenticated", 401);
  if (env.DATA_SERVICE_KEY && token === env.DATA_SERVICE_KEY) {
    const acting = (request.headers.get("x-hyn-user-id") ?? "").trim();
    if (!acting) return serviceSession();
    if (!USER_ID.test(acting)) throw new RpcError("not authenticated", 401);
    const rawEmail = (request.headers.get("x-hyn-user-email") ?? "").trim();
    const email = rawEmail.includes("@") ? rawEmail.slice(0, 320) : null;
    const profile = await ensureProfile(env.DB, acting, email, env.BOOTSTRAP_EMAIL || null);
    return { userId: acting, email: email ?? profile.email, profile, service: false };
  }
  try {
    const user = await verifySupabaseJwt(token, {
      secret: env.SUPABASE_JWT_SECRET || undefined,
      issuer: env.SUPABASE_JWT_ISS || undefined,
      jwksUrl: jwksUrl(env),
    });
    const profile = await ensureProfile(env.DB, user.id, user.email, env.BOOTSTRAP_EMAIL || null);
    return { userId: user.id, email: user.email, profile, service: false };
  } catch (error) {
    if (error instanceof RpcError) throw error;
    throw new RpcError("not authenticated", 401);
  }
}

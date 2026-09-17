import assert from "node:assert/strict";
import { test } from "node:test";
import { jsonFromUnknown, isD1WriteLimit } from "../src/http.ts";
import { sessionFromRequest } from "../src/session.ts";
import type { Profile } from "../src/types.ts";

const USER = "11111111-1111-4111-8111-111111111111";

function mockDb(existing: Profile | null = null, failWrites = false) {
  const profiles = new Map<string, Profile>();
  if (existing) profiles.set(existing.id, existing);
  return {
    prepare(sql: string) {
      return {
        bind(...args: unknown[]) {
          return {
            async first() {
              if (sql.includes("FROM profiles WHERE id")) return profiles.get(String(args[0])) ?? null;
              if (sql.includes("COUNT(*)")) return { n: profiles.size };
              return null;
            },
            async run() {
              if (failWrites) {
                throw new Error("D1_ERROR: Your account has exceeded D1's free tier daily row write limit. Upgrade to a paid plan or wait until tomorrow (midnight UTC) to continue.");
              }
              if (sql.includes("INSERT INTO profiles")) {
                const now = String(args[3]);
                profiles.set(String(args[0]), {
                  id: String(args[0]),
                  email: typeof args[1] === "string" ? args[1] : null,
                  full_name: null,
                  role: args[2] as Profile["role"],
                  status: "active",
                  suspended_reason: null,
                  created_at: now,
                  updated_at: now,
                });
              }
              return { success: true, results: [], meta: {} };
            },
            async all() {
              return { success: true, results: [], meta: {} };
            },
          };
        },
      };
    },
  } as unknown as D1Database;
}

function env(db: D1Database): Env {
  return { DB: db, DATA_SERVICE_KEY: "svc-secret" };
}

test("service key without impersonation is the internal super-admin session", async () => {
  const session = await sessionFromRequest(new Request("https://d1.test/rpc/x", {
    headers: { authorization: "Bearer svc-secret" },
  }), env(mockDb()));
  assert.equal(session.service, true);
  assert.equal(session.userId, "service");
  assert.equal(session.profile.role, "super_admin");
});

test("service key with x-hyn-user-id loads that user's portal session", async () => {
  const profile: Profile = {
    id: USER,
    email: "owner@example.test",
    full_name: null,
    role: "monitor",
    status: "active",
    suspended_reason: null,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
  };
  const session = await sessionFromRequest(new Request("https://d1.test/rpc/hyn_list_nodes", {
    headers: {
      authorization: "Bearer svc-secret",
      "x-hyn-user-id": USER,
      "x-hyn-user-email": "owner@example.test",
    },
  }), env(mockDb(profile)));
  assert.equal(session.service, false);
  assert.equal(session.userId, USER);
  assert.equal(session.profile.role, "monitor");
  assert.equal(session.email, "owner@example.test");
});

test("rejects impersonation that is not a user id", async () => {
  await assert.rejects(
    () => sessionFromRequest(new Request("https://d1.test/rpc/x", {
      headers: { authorization: "Bearer svc-secret", "x-hyn-user-id": "service" },
    }), env(mockDb())),
    /not authenticated/,
  );
});

test("existing users still sign in when D1 is out of daily writes", async () => {
  const profile: Profile = {
    id: USER,
    email: "owner@example.test",
    full_name: null,
    role: "monitor",
    status: "active",
    suspended_reason: null,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
  };
  const session = await sessionFromRequest(new Request("https://d1.test/rpc/hyn_profile", {
    headers: {
      authorization: "Bearer svc-secret",
      "x-hyn-user-id": USER,
      "x-hyn-user-email": "other@example.test",
    },
  }), env(mockDb(profile, true)));
  assert.equal(session.userId, USER);
  assert.equal(session.profile.role, "monitor");
  assert.equal(session.profile.status, "active");
});

test("D1 write-limit errors are a 503, not a broken dashboard", async () => {
  assert.equal(isD1WriteLimit(new Error("D1_ERROR: Your account has exceeded D1's free tier daily row write limit.")), true);
  const res = jsonFromUnknown(new Error("D1_ERROR: Your account has exceeded D1's free tier daily row write limit."));
  assert.equal(res.status, 503);
});

import test from "node:test";
import assert from "node:assert/strict";
import { permissions, normalizeRole } from "./permissions.ts";

test("only super admins can change machines, configuration, and sharing", () => {
  for (const role of ["viewer", "monitor", "admin", "unknown", "user"]) {
    assert.equal(permissions(role).canWrite, false, role);
  }
  assert.equal(permissions("super_admin").canWrite, true);
});
test("admins can promote admins but cannot operate machines", () => {
  assert.deepEqual(permissions("admin"), {
    canWrite: false,
    canSync: false,
    canRequest: false,
    canAdmin: true,
  });
});
test("monitors can refresh readings and request relayers; viewers are read only", () => {
  assert.equal(permissions("monitor").canSync, true);
  assert.equal(permissions("monitor").canRequest, true);
  assert.deepEqual(permissions("viewer"), {
    canWrite: false,
    canSync: false,
    canRequest: false,
    canAdmin: false,
  });
});
test("missing or legacy roles fail closed until the database is migrated", () => {
  for (const role of [null, undefined, "user", "owner", "SUPER_ADMIN"]) {
    assert.equal(normalizeRole(role), "viewer");
    assert.equal(permissions(role).canWrite, false);
  }
});

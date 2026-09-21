import test from "node:test";
import assert from "node:assert/strict";
import { permissions, normalizeRole } from "./permissions.ts";

test("only super admins can change machines, configuration, and sharing", () => {
  for (const role of ["viewer", "monitor", "maintainer", "admin", "unknown", "user"]) {
    assert.equal(permissions(role).canWrite, false, role);
  }
  assert.equal(permissions("super_admin").canWrite, true);
});
test("admins can promote admins but cannot operate machines", () => {
  assert.deepEqual(permissions("admin"), {
    canWrite: false,
    canLink: true,
    canSync: false,
    canRequest: false,
    canAdmin: true,
    canViewFleet: true,
    canNotify: true,
    isMaintainer: false,
  });
});
test("monitors can refresh readings and request relayers; viewers are read only", () => {
  assert.equal(permissions("monitor").canSync, true);
  assert.equal(permissions("monitor").canRequest, true);
  assert.deepEqual(permissions("viewer"), {
    canWrite: false,
    canLink: false,
    canSync: false,
    canRequest: false,
    canAdmin: false,
    canViewFleet: false,
    canNotify: false,
    isMaintainer: false,
  });
});
// The whole point of the role: fleet-wide sight and the ability to send, with no
// administrative write power. If canAdmin or canWrite ever goes true here, a
// monitoring account has silently become an administrator.
test("a maintainer sees every server and can notify, but administers nothing", () => {
  assert.deepEqual(permissions("maintainer"), {
    canWrite: false,
    canLink: false,
    canSync: true,
    canRequest: false,
    canAdmin: false,
    canViewFleet: true,
    canNotify: true,
    isMaintainer: true,
  });
});
test("only staff and maintainers resolve the combined fleet view", () => {
  for (const role of ["super_admin", "admin", "maintainer"]) {
    assert.equal(permissions(role).canViewFleet, true, role);
  }
  for (const role of ["viewer", "monitor", "user", null, undefined]) {
    assert.equal(permissions(role).canViewFleet, false, String(role));
  }
});
test("missing or legacy roles fail closed until the database is migrated", () => {
  for (const role of [null, undefined, "user", "owner", "SUPER_ADMIN"]) {
    assert.equal(normalizeRole(role), "viewer");
    assert.equal(permissions(role).canWrite, false);
  }
});

test("active account roles can pair their own devices without operational admin rights", () => {
  for (const role of ["monitor", "admin", "super_admin"]) assert.equal(permissions(role).canLink, true, role);
  // A maintainer monitors machines other people own; pairing is not part of it.
  for (const role of ["viewer", "maintainer", "user", null, undefined]) assert.equal(permissions(role).canLink, false, String(role));
});

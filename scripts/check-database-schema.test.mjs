import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { test } from "node:test";

async function runGate(reply) {
  const server = createServer((request, response) => {
    const name = request.url.split("/").at(-1);
    const result = reply(name);
    response.writeHead(result.status, { "Content-Type": "application/json" });
    response.end(JSON.stringify(result.body));
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  try {
    const child = spawn(process.execPath, [new URL("./check-database-schema.mjs", import.meta.url).pathname]);
    let output = "";
    child.stdout.on("data", chunk => { output += chunk; });
    child.stderr.on("data", chunk => { output += chunk; });
    child.stdin.end(JSON.stringify({
      NEXT_PUBLIC_SUPABASE_URL: `http://127.0.0.1:${server.address().port}`,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "release-gate-test-key",
    }));
    const code = await new Promise((resolve, reject) => {
      child.on("close", resolve);
      child.on("error", reject);
    });
    return { code, output };
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

const denied = () => ({ status: 401, body: { code: "42501", message: "permission denied" } });

for (const missing of ["hyn_dashboard_accounts", "hyn_is_super_admin"]) {
  test(`release fails when ${missing} is missing even if server access functions exist`, async () => {
    const result = await runGate(name => name === missing
      ? { status: 404, body: { code: "PGRST202", message: "function missing" } }
      : denied());
    assert.notEqual(result.code, 0);
    assert.match(result.output, new RegExp(missing));
    assert.match(result.output, /PGRST202/);
  });
}

test("release accepts installed functions that deny anonymous access", async () => {
  const result = await runGate(denied);
  assert.equal(result.code, 0, result.output);
});

test("release rejects anonymous dashboard access", async () => {
  const result = await runGate(name => name === "hyn_dashboard_accounts"
    ? { status: 200, body: [] }
    : denied());
  assert.notEqual(result.code, 0);
  assert.match(result.output, /hyn_dashboard_accounts/);
});

import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { applyEmailTemplate } from "./cloud-email.ts";
import { defaultTemplateHtml, sampleContentFor } from "./email-template-defaults.ts";
import { notificationTemplateKeys } from "./types.ts";

// The schema lives in the CLI repo root (supabase/), which the portal-only
// deployment branch does not carry. Resolve it from either layout and state
// plainly when it is absent, rather than passing on a file we never read.
const migrationCandidates = [
  "../../supabase/migrations/20260921150000_all_email_templates.sql",
  "../supabase/migrations/20260921150000_all_email_templates.sql",
];
function readMigration(): string | null {
  for (const candidate of migrationCandidates) {
    try {
      return readFileSync(new URL(candidate, import.meta.url), "utf8");
    } catch {
      continue;
    }
  }
  return null;
}
const migration = readMigration();

const keysFrom = (list: string) =>
  [...list.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]).sort();

// The set of editable templates is declared three times -- in TypeScript, in the
// table's CHECK constraint, and again inside the save RPC, which validates
// independently because it is the boundary a browser session actually reaches.
// Drift between them does not fail loudly: it presents as "the panel lists a
// template and refuses to save it", which is exactly the class of bug this
// change was fixing in the first place.
test("template keys agree across TypeScript, the CHECK constraint and the save RPC", (t) => {
  if (!migration) return t.skip("schema migrations are not part of this checkout");
  const expected = [...notificationTemplateKeys].sort();

  const check = migration.match(/check \(template_key in \(([^)]+)\)\)/);
  assert.ok(check, "the migration must declare a template_key CHECK constraint");
  assert.deepEqual(keysFrom(check[1]), expected, "CHECK constraint drifted from notificationTemplateKeys");

  const rpc = migration.match(/p_template_key not in \(([^)]+)\)/);
  assert.ok(rpc, "the save RPC must validate p_template_key");
  assert.deepEqual(keysFrom(rpc[1]), expected, "save RPC drifted from notificationTemplateKeys");
});

// A key that is allowed but has no row cannot be edited: hyn_admin_save_template
// updates by key and raises "not installed" when the row is missing, so the panel
// would list it and then refuse the save.
test("every allowed template key has a row to edit", (t) => {
  if (!migration) return t.skip("schema migrations are not part of this checkout");
  const seeded = new Set([
    ...[...migration.matchAll(/^\s*\('([a-z_]+)',\s*'/gm)].map((match) => match[1]),
    // The original three are seeded by schema.sql rather than this migration.
    "alert", "report", "system",
  ]);
  for (const key of notificationTemplateKeys) {
    assert.ok(seeded.has(key), `${key} is allowed but never seeded, so it cannot be saved`);
  }
});

test("the three emails that used to bypass templates are now covered", () => {
  for (const key of ["signin", "device", "first_report"] as const) {
    assert.ok(
      (notificationTemplateKeys as readonly string[]).includes(key),
      `${key} must be editable from the admin panel`,
    );
  }
});

// The shipped default has to survive the sanitiser untouched. If applyEmailTemplate
// stripped part of it, every email would render with a silently mangled wrapper and
// the preview would still look fine, because the preview runs the same stripper.
test("the default wrapper passes the sanitiser unchanged and keeps its placeholders", () => {
  for (const key of notificationTemplateKeys) {
    const html = defaultTemplateHtml(key);
    assert.ok(html.includes("{{content}}"), `${key} default must contain {{content}}`);

    const applied = applyEmailTemplate(html, {
      subject: "S", hostname: "H", severity: "info", version: "V", content: "<p>BODY</p>",
    });
    // Placeholders substituted, body present, and the wrapper's own structure intact.
    assert.ok(applied.includes("<p>BODY</p>"), `${key} lost the generated body`);
    assert.ok(applied.includes("H"), `${key} lost {{hostname}}`);
    assert.doesNotMatch(applied, /\{\{(content|hostname|version|severity|subject)\}\}/, `${key} left a placeholder unsubstituted`);
    // The table scaffold the layout depends on must not have been stripped.
    const tables = (applied.match(/<table/g) ?? []).length;
    assert.equal(tables, (html.match(/<table/g) ?? []).length, `${key} had tables stripped by the sanitiser`);
  }
});

// Mirrors hyn_admin_save_template's validation. A default the database would reject
// is a default the "Restore default" button cannot save.
test("the default wrapper would be accepted by the save RPC", () => {
  for (const key of notificationTemplateKeys) {
    const html = defaultTemplateHtml(key);
    assert.doesNotMatch(html, /<\s*(script|iframe|object|embed|form)[\s>]/i, `${key} contains a forbidden tag`);
    assert.doesNotMatch(html, /\son[a-z]+\s*=/i, `${key} contains an inline event handler`);
    assert.ok(new TextEncoder().encode(html).length <= 100_000, `${key} exceeds 100 KB`);
  }
});

test("sample preview content is produced for every template", () => {
  for (const key of notificationTemplateKeys) {
    const sample = sampleContentFor(key);
    assert.ok(sample.length > 40, `${key} has no meaningful sample content to preview`);
    assert.doesNotMatch(sample, /undefined|NaN|\[object Object\]/, `${key} sample leaked a broken value`);
  }
});

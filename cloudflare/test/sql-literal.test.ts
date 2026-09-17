import assert from "node:assert/strict";
import { test } from "node:test";
import { insertSql, sqlLiteral } from "../src/sql-literal.ts";

test("sql literals keep nulls, booleans and quotes safe", () => {
  assert.equal(sqlLiteral(null), "NULL");
  assert.equal(sqlLiteral(true), "1");
  assert.equal(sqlLiteral(false), "0");
  assert.equal(sqlLiteral(12), "12");
  assert.equal(sqlLiteral("O'Hara"), "'O''Hara'");
  assert.equal(sqlLiteral({ a: 1 }), `'{"a":1}'`);
});

test("insert statements bind selected columns only", () => {
  const sql = insertSql("nodes", ["id", "is_demo", "config"], {
    id: "n1",
    is_demo: false,
    config: { cloud_storage: "local" },
    extra: "ignore",
  });
  assert.equal(
    sql,
    `INSERT OR REPLACE INTO nodes (id, is_demo, config) VALUES ('n1', 0, '{"cloud_storage":"local"}')`,
  );
});

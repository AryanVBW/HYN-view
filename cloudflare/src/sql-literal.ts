export function sqlLiteral(value: unknown): string {
  if (value === null || value === undefined) return "NULL";
  if (typeof value === "boolean") return value ? "1" : "0";
  if (typeof value === "number") return Number.isFinite(value) ? String(value) : "NULL";
  if (typeof value === "bigint") return String(value);
  if (typeof value === "object") return sqlLiteral(JSON.stringify(value));
  return `'${String(value).replace(/'/g, "''")}'`;
}

export function pick(row: Record<string, unknown>, columns: string[]): unknown[] {
  return columns.map((column) => row[column] ?? null);
}

export function insertSql(table: string, columns: string[], row: Record<string, unknown>): string {
  return `INSERT OR REPLACE INTO ${table} (${columns.join(", ")}) VALUES (${pick(row, columns).map(sqlLiteral).join(", ")})`;
}

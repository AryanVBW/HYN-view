export async function count(
  db: D1Database,
  sql: string,
  ...binds: unknown[]
): Promise<number> {
  const row = await db.prepare(sql).bind(...binds).first<{ n: number }>();
  return Number(row?.n ?? 0);
}

export function asBool(value: unknown): boolean {
  return value === 1 || value === true || value === "1";
}

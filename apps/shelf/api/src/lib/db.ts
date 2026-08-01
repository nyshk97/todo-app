export type Bindings = {
  DB: D1Database;
  ATTACHMENTS: R2Bucket;
  API_SECRET: string;
  TODO_APP_API_URL: string;
  TODO_APP_API_SECRET: string;
};

export function generateId(): string {
  return crypto.randomUUID();
}

export function nowJST(): string {
  return new Date(Date.now() + 9 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 19)
    .replace("T", " ");
}

export function todayJST(): string {
  return new Date(Date.now() + 9 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

/**
 * Build a dynamic UPDATE query handling D1's null binding issue.
 * For null values, uses `column = NULL` directly in SQL instead of binding.
 */
export function buildUpdate(
  table: string,
  id: string,
  fields: Record<string, unknown>,
  now: string
): { sql: string; bindings: unknown[] } {
  const setClauses: string[] = [];
  const bindings: unknown[] = [];

  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined) continue;
    if (value === null) {
      setClauses.push(`${key} = NULL`);
    } else {
      setClauses.push(`${key} = ?`);
      bindings.push(value);
    }
  }

  setClauses.push("updated_at = ?");
  bindings.push(now);
  bindings.push(id);

  const sql = `UPDATE ${table} SET ${setClauses.join(", ")} WHERE id = ?`;
  return { sql, bindings };
}

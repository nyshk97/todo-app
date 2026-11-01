import { env } from "cloudflare:test";
import app from "../index";

export async function req(
  path: string,
  opts?: { method?: string; body?: unknown; form?: FormData }
): Promise<Response> {
  const init: RequestInit = { method: opts?.method ?? "GET" };
  const headers: Record<string, string> = {
    Authorization: `Bearer ${env.API_SECRET}`,
  };
  if (opts?.body) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(opts.body);
  } else if (opts?.form) {
    init.body = opts.form;
  }
  init.headers = headers;
  return app.fetch(new Request(`http://localhost${path}`, init), env);
}

export async function json<T = unknown>(res: Response): Promise<T> {
  return res.json() as Promise<T>;
}

// migrations/ の内容をテスト用 DB に流す。列を足したらここも更新する
const SCHEMA = `
  CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS sections (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    section_id TEXT REFERENCES sections(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    due_date TEXT,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    archived_at TEXT,
    repeat_unit TEXT,
    repeat_interval INTEGER,
    repeat_anchor_day INTEGER
  );
  CREATE TABLE IF NOT EXISTS comments (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY,
    comment_id TEXT NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    content_type TEXT NOT NULL,
    size INTEGER NOT NULL,
    r2_key TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
`;

export async function applySchema(): Promise<void> {
  for (const stmt of SCHEMA.split(";").filter((s) => s.trim())) {
    await env.DB.prepare(stmt).run();
  }
}

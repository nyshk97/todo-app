import { Hono } from "hono";
import type { Bindings } from "../lib/db";
import { generateId, nowJST, buildUpdate } from "../lib/db";
import type { ReorderRequest } from "@todo-shelf/shared";

const app = new Hono<{ Bindings: Bindings }>();

// GET /projects/:id/sections
app.get("/projects/:id/sections", async (c) => {
  const projectId = c.req.param("id");
  const results = await c.env.DB.prepare(
    "SELECT * FROM sections WHERE project_id = ? ORDER BY position"
  )
    .bind(projectId)
    .all();
  return c.json(results.results);
});

// POST /projects/:id/sections
app.post("/projects/:id/sections", async (c) => {
  const projectId = c.req.param("id");
  const body = await c.req.json<{ name: string }>();
  if (!body.name) return c.json({ error: "name is required" }, 400);

  const id = generateId();
  const now = nowJST();
  const maxPos = await c.env.DB.prepare(
    "SELECT COALESCE(MAX(position), -1) as max_pos FROM sections WHERE project_id = ?"
  )
    .bind(projectId)
    .first<{ max_pos: number }>();

  await c.env.DB.prepare(
    "INSERT INTO sections (id, project_id, name, position, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)"
  )
    .bind(id, projectId, body.name, (maxPos?.max_pos ?? -1) + 1, now, now)
    .run();

  const section = await c.env.DB.prepare(
    "SELECT * FROM sections WHERE id = ?"
  )
    .bind(id)
    .first();
  return c.json(section, 201);
});

// PATCH /sections/:id
app.patch("/sections/:id", async (c) => {
  const id = c.req.param("id");
  const body = await c.req.json<{ name?: string; position?: number }>();

  const existing = await c.env.DB.prepare(
    "SELECT id FROM sections WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  const { sql, bindings } = buildUpdate("sections", id, body, nowJST());
  await c.env.DB.prepare(sql).bind(...bindings).run();

  const section = await c.env.DB.prepare(
    "SELECT * FROM sections WHERE id = ?"
  )
    .bind(id)
    .first();
  return c.json(section);
});

// DELETE /sections/:id
app.delete("/sections/:id", async (c) => {
  const id = c.req.param("id");
  const existing = await c.env.DB.prepare(
    "SELECT id FROM sections WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  await c.env.DB.prepare("DELETE FROM sections WHERE id = ?").bind(id).run();
  return c.body(null, 204);
});

// PATCH /projects/:id/sections/reorder
app.patch("/projects/:id/sections/reorder", async (c) => {
  const body = await c.req.json<ReorderRequest>();
  const now = nowJST();
  const stmts = body.items.map((item) =>
    c.env.DB.prepare(
      "UPDATE sections SET position = ?, updated_at = ? WHERE id = ?"
    ).bind(item.position, now, item.id)
  );
  await c.env.DB.batch(stmts);
  return c.json({ ok: true });
});

export default app;

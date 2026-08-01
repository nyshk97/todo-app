import { Hono } from "hono";
import type { Bindings } from "../lib/db";
import { generateId, nowJST, buildUpdate } from "../lib/db";

const app = new Hono<{ Bindings: Bindings }>();

// GET /projects
app.get("/projects", async (c) => {
  const results = await c.env.DB.prepare(
    "SELECT * FROM projects ORDER BY position"
  ).all();
  return c.json(results.results);
});

// POST /projects
app.post("/projects", async (c) => {
  const body = await c.req.json<{ name: string }>();
  if (!body.name) return c.json({ error: "name is required" }, 400);

  const id = generateId();
  const now = nowJST();
  const maxPos = await c.env.DB.prepare(
    "SELECT COALESCE(MAX(position), -1) as max_pos FROM projects"
  ).first<{ max_pos: number }>();

  await c.env.DB.prepare(
    "INSERT INTO projects (id, name, position, created_at, updated_at) VALUES (?, ?, ?, ?, ?)"
  )
    .bind(id, body.name, (maxPos?.max_pos ?? -1) + 1, now, now)
    .run();

  const project = await c.env.DB.prepare(
    "SELECT * FROM projects WHERE id = ?"
  )
    .bind(id)
    .first();
  return c.json(project, 201);
});

// PATCH /projects/:id
app.patch("/projects/:id", async (c) => {
  const id = c.req.param("id");
  const body = await c.req.json<{ name?: string; position?: number }>();

  const existing = await c.env.DB.prepare(
    "SELECT id FROM projects WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  const { sql, bindings } = buildUpdate("projects", id, body, nowJST());
  await c.env.DB.prepare(sql).bind(...bindings).run();

  const project = await c.env.DB.prepare(
    "SELECT * FROM projects WHERE id = ?"
  )
    .bind(id)
    .first();
  return c.json(project);
});

// DELETE /projects/:id
app.delete("/projects/:id", async (c) => {
  const id = c.req.param("id");
  const existing = await c.env.DB.prepare(
    "SELECT id FROM projects WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  await c.env.DB.prepare("DELETE FROM projects WHERE id = ?").bind(id).run();
  return c.body(null, 204);
});

export default app;

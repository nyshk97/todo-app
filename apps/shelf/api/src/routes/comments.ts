import { Hono } from "hono";
import type { Bindings } from "../lib/db";
import { generateId, nowJST, buildUpdate } from "../lib/db";

const app = new Hono<{ Bindings: Bindings }>();

// GET /tasks/:id/comments
app.get("/tasks/:id/comments", async (c) => {
  const taskId = c.req.param("id");
  const results = await c.env.DB.prepare(
    "SELECT * FROM comments WHERE task_id = ? ORDER BY created_at"
  )
    .bind(taskId)
    .all();
  return c.json(results.results);
});

// POST /tasks/:id/comments
app.post("/tasks/:id/comments", async (c) => {
  const taskId = c.req.param("id");
  const body = await c.req.json<{ content: string }>();
  if (!body.content) return c.json({ error: "content is required" }, 400);

  const id = generateId();
  const now = nowJST();

  await c.env.DB.prepare(
    "INSERT INTO comments (id, task_id, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?)"
  )
    .bind(id, taskId, body.content, now, now)
    .run();

  const comment = await c.env.DB.prepare(
    "SELECT * FROM comments WHERE id = ?"
  )
    .bind(id)
    .first();
  return c.json(comment, 201);
});

// PATCH /comments/:id
app.patch("/comments/:id", async (c) => {
  const id = c.req.param("id");
  const body = await c.req.json<{ content: string }>();

  const existing = await c.env.DB.prepare(
    "SELECT id FROM comments WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  const { sql, bindings } = buildUpdate(
    "comments",
    id,
    { content: body.content },
    nowJST()
  );
  await c.env.DB.prepare(sql).bind(...bindings).run();

  const comment = await c.env.DB.prepare(
    "SELECT * FROM comments WHERE id = ?"
  )
    .bind(id)
    .first();
  return c.json(comment);
});

// DELETE /comments/:id
app.delete("/comments/:id", async (c) => {
  const id = c.req.param("id");
  const existing = await c.env.DB.prepare(
    "SELECT id FROM comments WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  await c.env.DB.prepare("DELETE FROM comments WHERE id = ?").bind(id).run();
  return c.body(null, 204);
});

export default app;

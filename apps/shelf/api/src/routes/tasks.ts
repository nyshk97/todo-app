import { Hono } from "hono";
import type { Bindings } from "../lib/db";
import { generateId, nowJST, todayJST, buildUpdate } from "../lib/db";
import type {
  CreateTaskRequest,
  UpdateTaskRequest,
  ReorderRequest,
} from "@todo-shelf/shared";

const app = new Hono<{ Bindings: Bindings }>();

// GET /tasks/upcoming
app.get("/tasks/upcoming", async (c) => {
  const days = Number(c.req.query("days") ?? 3);
  const today = todayJST();
  const endDate = new Date(Date.now() + 9 * 60 * 60 * 1000 + days * 86400000)
    .toISOString()
    .slice(0, 10);

  const results = await c.env.DB.prepare(
    `SELECT t.*, p.name as project_name
     FROM tasks t JOIN projects p ON t.project_id = p.id
     WHERE t.due_date IS NOT NULL AND t.due_date <= ?
     ORDER BY t.due_date, t.position`
  )
    .bind(endDate)
    .all();
  return c.json(results.results);
});

// PATCH /tasks/reorder
app.patch("/tasks/reorder", async (c) => {
  const body = await c.req.json<ReorderRequest>();
  const now = nowJST();
  const stmts = body.items.map((item) =>
    c.env.DB.prepare(
      "UPDATE tasks SET position = ?, updated_at = ? WHERE id = ?"
    ).bind(item.position, now, item.id)
  );
  await c.env.DB.batch(stmts);
  return c.json({ ok: true });
});

// GET /projects/:id/tasks
app.get("/projects/:id/tasks", async (c) => {
  const projectId = c.req.param("id");
  const results = await c.env.DB.prepare(
    "SELECT * FROM tasks WHERE project_id = ? ORDER BY position"
  )
    .bind(projectId)
    .all();
  return c.json(results.results);
});

// POST /tasks
app.post("/tasks", async (c) => {
  const body = await c.req.json<CreateTaskRequest>();
  if (!body.title || !body.project_id) {
    return c.json({ error: "title and project_id are required" }, 400);
  }

  const id = generateId();
  const now = nowJST();

  const maxPos = await c.env.DB.prepare(
    body.section_id
      ? "SELECT COALESCE(MAX(position), -1) as max_pos FROM tasks WHERE project_id = ? AND section_id = ?"
      : "SELECT COALESCE(MAX(position), -1) as max_pos FROM tasks WHERE project_id = ? AND section_id IS NULL"
  )
    .bind(
      ...(body.section_id
        ? [body.project_id, body.section_id]
        : [body.project_id])
    )
    .first<{ max_pos: number }>();

  // Handle nullable fields with raw SQL
  const sectionClause = body.section_id ? "?" : "NULL";
  const dueDateClause = body.due_date ? "?" : "NULL";
  const bindings: unknown[] = [id, body.project_id];
  if (body.section_id) bindings.push(body.section_id);
  bindings.push(body.title);
  if (body.due_date) bindings.push(body.due_date);
  bindings.push((maxPos?.max_pos ?? -1) + 1, now, now);

  await c.env.DB.prepare(
    `INSERT INTO tasks (id, project_id, section_id, title, due_date, position, created_at, updated_at)
     VALUES (?, ?, ${sectionClause}, ?, ${dueDateClause}, ?, ?, ?)`
  )
    .bind(...bindings)
    .run();

  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first();
  return c.json(task, 201);
});

// PATCH /tasks/:id
app.patch("/tasks/:id", async (c) => {
  const id = c.req.param("id");
  const body = await c.req.json<UpdateTaskRequest>();

  const existing = await c.env.DB.prepare(
    "SELECT id FROM tasks WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  const { sql, bindings } = buildUpdate("tasks", id, { ...body }, nowJST());
  await c.env.DB.prepare(sql).bind(...bindings).run();

  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first();
  return c.json(task);
});

// DELETE /tasks/:id
app.delete("/tasks/:id", async (c) => {
  const id = c.req.param("id");
  const existing = await c.env.DB.prepare(
    "SELECT id FROM tasks WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  await c.env.DB.prepare("DELETE FROM tasks WHERE id = ?").bind(id).run();
  return c.body(null, 204);
});

// POST /tasks/:id/move-to-today
app.post("/tasks/:id/move-to-today", async (c) => {
  const id = c.req.param("id");
  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first<{ title: string }>();
  if (!task) return c.json({ error: "Not found" }, 404);

  const res = await fetch(
    `${c.env.TODO_APP_API_URL}/todos`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${c.env.TODO_APP_API_SECRET}`,
      },
      body: JSON.stringify({ title: task.title, date: todayJST() }),
    }
  );

  if (!res.ok) {
    return c.json({ error: "Failed to create todo in todo-app" }, 502);
  }

  await c.env.DB.prepare("DELETE FROM tasks WHERE id = ?").bind(id).run();
  return c.json({ ok: true });
});

export default app;

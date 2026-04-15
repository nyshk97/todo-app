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
     WHERE t.due_date IS NOT NULL AND t.due_date <= ? AND t.archived_at IS NULL
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

// GET /tasks/archived
app.get("/tasks/archived", async (c) => {
  const results = await c.env.DB.prepare(
    `SELECT t.*, p.name as project_name, COALESCE(cc.cnt, 0) as comment_count
     FROM tasks t
     JOIN projects p ON t.project_id = p.id
     LEFT JOIN (SELECT task_id, COUNT(*) as cnt FROM comments GROUP BY task_id) cc ON cc.task_id = t.id
     WHERE t.archived_at IS NOT NULL
     ORDER BY t.archived_at DESC`
  ).all();
  return c.json(results.results);
});

// POST /tasks/:id/restore
app.post("/tasks/:id/restore", async (c) => {
  const id = c.req.param("id");
  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first<{ id: string; project_id: string; section_id: string | null; archived_at: string | null }>();
  if (!task) return c.json({ error: "Not found" }, 404);
  if (!task.archived_at) return c.json({ error: "Task is not archived" }, 400);

  // Check if original section still exists
  let sectionId = task.section_id;
  if (sectionId) {
    const section = await c.env.DB.prepare("SELECT id FROM sections WHERE id = ?")
      .bind(sectionId)
      .first();
    if (!section) sectionId = null;
  }

  const now = nowJST();
  const maxPos = await c.env.DB.prepare(
    sectionId
      ? "SELECT COALESCE(MAX(position), -1) as max_pos FROM tasks WHERE project_id = ? AND section_id = ? AND archived_at IS NULL"
      : "SELECT COALESCE(MAX(position), -1) as max_pos FROM tasks WHERE project_id = ? AND section_id IS NULL AND archived_at IS NULL"
  )
    .bind(...(sectionId ? [task.project_id, sectionId] : [task.project_id]))
    .first<{ max_pos: number }>();

  const sectionClause = sectionId ? "section_id = ?" : "section_id = NULL";
  const bindings: unknown[] = [];
  if (sectionId) bindings.push(sectionId);
  bindings.push((maxPos?.max_pos ?? -1) + 1, now, id);

  await c.env.DB.prepare(
    `UPDATE tasks SET archived_at = NULL, ${sectionClause}, position = ?, updated_at = ? WHERE id = ?`
  )
    .bind(...bindings)
    .run();

  const restored = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first();
  return c.json(restored);
});

// GET /projects/:id/tasks
app.get("/projects/:id/tasks", async (c) => {
  const projectId = c.req.param("id");
  const results = await c.env.DB.prepare(
    `SELECT t.*, COALESCE(cc.cnt, 0) as comment_count
     FROM tasks t
     LEFT JOIN (SELECT task_id, COUNT(*) as cnt FROM comments GROUP BY task_id) cc ON cc.task_id = t.id
     WHERE t.project_id = ? AND t.archived_at IS NULL
     ORDER BY t.position`
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
      ? "SELECT COALESCE(MAX(position), -1) as max_pos FROM tasks WHERE project_id = ? AND section_id = ? AND archived_at IS NULL"
      : "SELECT COALESCE(MAX(position), -1) as max_pos FROM tasks WHERE project_id = ? AND section_id IS NULL AND archived_at IS NULL"
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

  // Delete R2 files for all comments on this task
  const attachments = await c.env.DB.prepare(
    `SELECT a.r2_key FROM attachments a
     JOIN comments c ON a.comment_id = c.id
     WHERE c.task_id = ?`
  )
    .bind(id)
    .all();

  for (const a of attachments.results) {
    await c.env.ATTACHMENTS.delete(a.r2_key as string);
  }

  await c.env.DB.prepare("DELETE FROM tasks WHERE id = ?").bind(id).run();
  return c.body(null, 204);
});

// POST /tasks/:id/move-to-today
app.post("/tasks/:id/move-to-today", async (c) => {
  const id = c.req.param("id");
  const task = await c.env.DB.prepare("SELECT * FROM tasks WHERE id = ?")
    .bind(id)
    .first();
  if (!task) return c.json({ error: "Not found" }, 404);

  // Shelf側でアーカイブのみ（todo-appへのPOSTはクライアント側で実行）
  const now = nowJST();
  await c.env.DB.prepare(
    "UPDATE tasks SET archived_at = ?, updated_at = ? WHERE id = ?"
  )
    .bind(now, now, id)
    .run();

  return c.json({ ok: true });
});

export default app;

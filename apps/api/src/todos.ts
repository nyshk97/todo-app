import { Hono } from "hono";
import { today, yesterday, isEditable } from "./date";

type Bindings = {
  DB: D1Database;
  API_SECRET: string;
};

const todos = new Hono<{ Bindings: Bindings }>();

// 自動繰り越し処理
async function carryOverIfNeeded(db: D1Database, todayStr: string) {
  // 今日のタスクが既にあれば繰り越し不要
  const existing = await db
    .prepare("SELECT COUNT(*) as count FROM todos WHERE date = ?")
    .bind(todayStr)
    .first<{ count: number }>();

  if (existing && existing.count > 0) return;

  // 前日の未完了タスクを取得
  const yesterdayStr = yesterday();
  const uncompleted = await db
    .prepare(
      "SELECT title, position, duration FROM todos WHERE date = ? AND completed = 0 ORDER BY position"
    )
    .bind(yesterdayStr)
    .all<{ title: string; position: number; duration: number | null }>();

  if (!uncompleted.results || uncompleted.results.length === 0) return;

  // 今日のタスクとしてコピー
  const stmt = db.prepare(
    "INSERT INTO todos (id, title, date, completed, position, carried_over, duration) VALUES (?, ?, ?, 0, ?, 1, ?)"
  );
  const batch = uncompleted.results.map((task, i) =>
    stmt.bind(crypto.randomUUID(), task.title, todayStr, i, task.duration)
  );
  await db.batch(batch);
}

// GET /todos?date=YYYY-MM-DD
todos.get("/", async (c) => {
  const date = c.req.query("date") || today();
  const todayStr = today();

  // 今日のタスク取得時は自動繰り越し
  if (date === todayStr) {
    await carryOverIfNeeded(c.env.DB, todayStr);
  }

  const result = await c.env.DB
    .prepare("SELECT * FROM todos WHERE date = ? ORDER BY completed ASC, position ASC")
    .bind(date)
    .all();

  return c.json({
    todos: result.results.map((row: Record<string, unknown>) => ({
      id: row.id,
      title: row.title,
      date: row.date,
      completed: row.completed === 1,
      position: row.position,
      carried_over: row.carried_over === 1,
      completed_at: row.completed_at ?? null,
      duration: row.duration ?? null,
      created_at: row.created_at,
      updated_at: row.updated_at,
    })),
    date,
    editable: isEditable(date),
  });
});

// POST /todos
todos.post("/", async (c) => {
  const body = await c.req.json<{ title: string }>();
  if (!body.title || body.title.trim() === "") {
    return c.json({ error: "title is required" }, 400);
  }

  const todayStr = today();
  const id = crypto.randomUUID();

  // 現在の最大 position を取得
  const max = await c.env.DB
    .prepare("SELECT MAX(position) as max_pos FROM todos WHERE date = ?")
    .bind(todayStr)
    .first<{ max_pos: number | null }>();
  const position = (max?.max_pos ?? -1) + 1;

  await c.env.DB
    .prepare(
      "INSERT INTO todos (id, title, date, position) VALUES (?, ?, ?, ?)"
    )
    .bind(id, body.title.trim(), todayStr, position)
    .run();

  const todo = await c.env.DB
    .prepare("SELECT * FROM todos WHERE id = ?")
    .bind(id)
    .first();

  return c.json(
    {
      ...todo,
      completed: (todo as Record<string, unknown>).completed === 1,
      carried_over: (todo as Record<string, unknown>).carried_over === 1,
      completed_at: (todo as Record<string, unknown>).completed_at ?? null,
      duration: (todo as Record<string, unknown>).duration ?? null,
    },
    201
  );
});

// PATCH /todos/:id
todos.patch("/:id", async (c) => {
  const id = c.req.param("id");
  const todo = await c.env.DB
    .prepare("SELECT * FROM todos WHERE id = ?")
    .bind(id)
    .first<Record<string, unknown>>();

  if (!todo) return c.json({ error: "Not found" }, 404);
  if (!isEditable(todo.date as string)) {
    return c.json({ error: "Cannot edit tasks older than 1 day" }, 403);
  }

  const body = await c.req.json<{
    title?: string;
    completed?: boolean;
    position?: number;
    duration?: number | null;
  }>();

  const updates: string[] = [];
  const values: unknown[] = [];

  if (body.title !== undefined) {
    updates.push("title = ?");
    values.push(body.title.trim());
  }
  if (body.completed !== undefined) {
    updates.push("completed = ?");
    values.push(body.completed ? 1 : 0);
    if (body.completed) {
      updates.push("completed_at = ?");
      values.push(new Date().toISOString());
    } else {
      updates.push("completed_at = NULL");
    }
  }
  if (body.position !== undefined) {
    updates.push("position = ?");
    values.push(body.position);
  }
  if (body.duration !== undefined) {
    if (body.duration === null) {
      updates.push("duration = NULL");
    } else {
      updates.push("duration = ?");
      values.push(body.duration);
    }
  }

  if (updates.length === 0) {
    return c.json({ error: "No fields to update" }, 400);
  }

  updates.push("updated_at = datetime('now')");
  values.push(id);

  await c.env.DB
    .prepare(`UPDATE todos SET ${updates.join(", ")} WHERE id = ?`)
    .bind(...values)
    .run();

  const updated = await c.env.DB
    .prepare("SELECT * FROM todos WHERE id = ?")
    .bind(id)
    .first();

  return c.json({
    ...updated,
    completed: (updated as Record<string, unknown>).completed === 1,
    carried_over: (updated as Record<string, unknown>).carried_over === 1,
    completed_at: (updated as Record<string, unknown>).completed_at ?? null,
    duration: (updated as Record<string, unknown>).duration ?? null,
  });
});

// DELETE /todos/:id
todos.delete("/:id", async (c) => {
  const id = c.req.param("id");
  const todo = await c.env.DB
    .prepare("SELECT * FROM todos WHERE id = ?")
    .bind(id)
    .first<Record<string, unknown>>();

  if (!todo) return c.json({ error: "Not found" }, 404);
  if (!isEditable(todo.date as string)) {
    return c.json({ error: "Cannot delete tasks older than 1 day" }, 403);
  }

  await c.env.DB.prepare("DELETE FROM todos WHERE id = ?").bind(id).run();
  return c.json({ ok: true });
});

// PATCH /todos/reorder
todos.patch("/", async (c) => {
  const body = await c.req.json<{
    items: { id: string; position: number }[];
  }>();

  if (!body.items || body.items.length === 0) {
    return c.json({ error: "items is required" }, 400);
  }

  const stmt = c.env.DB.prepare(
    "UPDATE todos SET position = ?, updated_at = datetime('now') WHERE id = ? AND date = ?"
  );
  const todayStr = today();
  const batch = body.items.map((item) =>
    stmt.bind(item.position, item.id, todayStr)
  );
  await c.env.DB.batch(batch);

  return c.json({ ok: true });
});

export { todos };

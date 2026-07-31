import { Hono } from "hono";
import { today, yesterday, isEditable } from "./date";

type Bindings = {
  DB: D1Database;
  API_SECRET: string;
};

const todos = new Hono<{ Bindings: Bindings }>();

// 自動繰り越し処理
// 「件数チェック→INSERT」を別々に走らせると同時アクセスで二重繰り越しになるため、
// ガード込みの1文で実行する（NOT EXISTS は文全体の評価前に確定する）
async function carryOverIfNeeded(db: D1Database, todayStr: string) {
  const yesterdayStr = yesterday();
  await db
    .prepare(
      `INSERT INTO todos (id, title, date, completed, position, carried_over)
       SELECT lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (random() & 3), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))),
              title, ?1, 0, position, 1
       FROM todos
       WHERE date = ?2 AND completed = 0
         AND NOT EXISTS (SELECT 1 FROM todos WHERE date = ?1)`
    )
    .bind(todayStr, yesterdayStr)
    .run();
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
    .prepare("SELECT * FROM todos WHERE date = ? ORDER BY completed ASC, completed_at DESC, position ASC")
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
      created_at: row.created_at,
      updated_at: row.updated_at,
    })),
    date,
    editable: isEditable(date),
  });
});

const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// POST /todos
// body.id (UUID) をクライアントが渡すと冪等になる: 同じ id の再送は新規作成せず
// 既存行をそのまま 200 で返す。リトライ・二度押しによる二重登録の防止用
todos.post("/", async (c) => {
  const body = await c.req.json<{ id?: string; title: string; date?: string }>();
  if (!body.title || body.title.trim() === "") {
    return c.json({ error: "title is required" }, 400);
  }
  if (body.id !== undefined && !uuidPattern.test(body.id)) {
    return c.json({ error: "id must be a UUID" }, 400);
  }

  const targetDate = body.date ?? today();
  if (!datePattern.test(targetDate)) {
    return c.json({ error: "date must be YYYY-MM-DD" }, 400);
  }
  if (!isEditable(targetDate)) {
    return c.json({ error: "Cannot create tasks outside editable date range" }, 403);
  }

  const id = body.id ?? crypto.randomUUID();

  // position の採番も含めて1文で行う（SELECT→INSERT の2段だと同時POSTで position が重複する）
  const result = await c.env.DB
    .prepare(
      "INSERT OR IGNORE INTO todos (id, title, date, position) SELECT ?, ?, ?, COALESCE(MAX(position), -1) + 1 FROM todos WHERE date = ?"
    )
    .bind(id, body.title.trim(), targetDate, targetDate)
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
    },
    result.meta.changes === 0 ? 200 : 201
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
    date?: string;
  }>();

  if (!body.items || body.items.length === 0) {
    return c.json({ error: "items is required" }, 400);
  }
  const ids = body.items.map((item) => item.id);
  if (new Set(ids).size !== ids.length) {
    return c.json({ error: "duplicate ids are not allowed" }, 400);
  }
  const targetDate = body.date ?? today();
  if (!datePattern.test(targetDate)) {
    return c.json({ error: "date must be YYYY-MM-DD" }, 400);
  }
  if (!isEditable(targetDate)) {
    return c.json({ error: "Cannot reorder tasks outside editable date range" }, 403);
  }

  const placeholders = ids.map(() => "?").join(", ");
  const matching = await c.env.DB
    .prepare(
      `SELECT COUNT(*) as count FROM todos WHERE date = ? AND id IN (${placeholders})`
    )
    .bind(targetDate, ...ids)
    .first<{ count: number }>();
  if ((matching?.count ?? 0) !== ids.length) {
    return c.json({ error: "Some items do not belong to the target date" }, 409);
  }

  const stmt = c.env.DB.prepare(
    "UPDATE todos SET position = ?, updated_at = datetime('now') WHERE id = ? AND date = ?"
  );
  const batch = body.items.map((item) =>
    stmt.bind(item.position, item.id, targetDate)
  );
  await c.env.DB.batch(batch);

  return c.json({ ok: true });
});

export { todos };

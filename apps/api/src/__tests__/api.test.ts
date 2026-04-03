import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";
import { Miniflare } from "miniflare";
import * as fs from "node:fs";
import * as path from "node:path";
import { execSync } from "node:child_process";

let mf: Miniflare;

const AUTH = { Authorization: "Bearer test-secret" };
const JSON_HEADERS = { ...AUTH, "Content-Type": "application/json" };

// esbuild でバンドルしてから Miniflare に渡す
function buildWorker(): string {
  const outfile = path.join(__dirname, "../../dist/_test_worker.mjs");
  execSync(
    `npx esbuild src/index.ts --bundle --format=esm --outfile=${outfile} --platform=neutral`,
    { cwd: path.join(__dirname, "../..") }
  );
  return outfile;
}

async function createTodo(title: string) {
  const res = await mf.dispatchFetch("http://localhost/todos", {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify({ title }),
  });
  return res.json() as Promise<Record<string, unknown>>;
}

async function getTodos(date?: string) {
  const url = date
    ? `http://localhost/todos?date=${date}`
    : "http://localhost/todos";
  const res = await mf.dispatchFetch(url, { headers: AUTH });
  return res.json() as Promise<{
    todos: Record<string, unknown>[];
    date: string;
    editable: boolean;
  }>;
}

async function getDb() {
  return await mf.getD1Database("DB");
}

describe("API", () => {
  beforeEach(async () => {
    const scriptPath = buildWorker();
    mf = new Miniflare({
      modules: true,
      scriptPath,
      d1Databases: { DB: "test-db" },
      bindings: { API_SECRET: "test-secret" },
      compatibilityDate: "2025-04-01",
    });

    const db = await getDb();
    await db.exec("CREATE TABLE IF NOT EXISTS todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, date TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, carried_over INTEGER NOT NULL DEFAULT 0, completed_at TEXT, duration INTEGER, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')));");
    await db.exec("CREATE INDEX IF NOT EXISTS idx_todos_date ON todos(date);");
    await db.exec("DELETE FROM todos");
  });

  afterEach(async () => {
    await mf.dispose();
  });

  describe("認証", () => {
    it("トークンなしで 401", async () => {
      const res = await mf.dispatchFetch("http://localhost/todos");
      expect(res.status).toBe(401);
    });

    it("不正トークンで 401", async () => {
      const res = await mf.dispatchFetch("http://localhost/todos", {
        headers: { Authorization: "Bearer wrong" },
      });
      expect(res.status).toBe(401);
    });

    it("正しいトークンで 200", async () => {
      const res = await mf.dispatchFetch("http://localhost/todos", {
        headers: AUTH,
      });
      expect(res.status).toBe(200);
    });
  });

  describe("CRUD", () => {
    it("タスクを追加して取得できる", async () => {
      const todo = await createTodo("テスト");
      expect(todo.title).toBe("テスト");
      expect(todo.completed).toBe(false);
      expect(todo.position).toBe(0);

      const data = await getTodos();
      expect(data.todos).toHaveLength(1);
      expect(data.todos[0].title).toBe("テスト");
    });

    it("空タイトルで 400", async () => {
      const res = await mf.dispatchFetch("http://localhost/todos", {
        method: "POST",
        headers: JSON_HEADERS,
        body: JSON.stringify({ title: "" }),
      });
      expect(res.status).toBe(400);
    });

    it("position は追加順にインクリメントされる", async () => {
      const t1 = await createTodo("1つ目");
      const t2 = await createTodo("2つ目");
      expect(t1.position).toBe(0);
      expect(t2.position).toBe(1);
    });

    it("完了に更新できる", async () => {
      const todo = await createTodo("タスク");
      const res = await mf.dispatchFetch(
        `http://localhost/todos/${todo.id}`,
        {
          method: "PATCH",
          headers: JSON_HEADERS,
          body: JSON.stringify({ completed: true }),
        }
      );
      const updated = (await res.json()) as Record<string, unknown>;
      expect(updated.completed).toBe(true);
    });

    it("削除できる", async () => {
      const todo = await createTodo("削除する");
      const res = await mf.dispatchFetch(
        `http://localhost/todos/${todo.id}`,
        { method: "DELETE", headers: AUTH }
      );
      expect(res.status).toBe(200);

      const data = await getTodos();
      expect(data.todos).toHaveLength(0);
    });

    it("存在しないIDで 404", async () => {
      const res = await mf.dispatchFetch(
        "http://localhost/todos/nonexistent",
        { method: "DELETE", headers: AUTH }
      );
      expect(res.status).toBe(404);
    });
  });

  describe("並べ替え", () => {
    it("reorder で position を一括更新できる", async () => {
      const t1 = await createTodo("A");
      const t2 = await createTodo("B");
      const t3 = await createTodo("C");

      await mf.dispatchFetch("http://localhost/todos", {
        method: "PATCH",
        headers: JSON_HEADERS,
        body: JSON.stringify({
          items: [
            { id: t3.id, position: 0 },
            { id: t1.id, position: 1 },
            { id: t2.id, position: 2 },
          ],
        }),
      });

      const data = await getTodos();
      expect(data.todos.map((t) => t.title)).toEqual(["C", "A", "B"]);
    });
  });

  describe("日付制限", () => {
    it("2日以上前のタスクは更新できない (403)", async () => {
      const db = await getDb();
      const twoDaysAgo = new Date();
      twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);
      const dateStr = twoDaysAgo.toISOString().slice(0, 10);

      await db
        .prepare(
          "INSERT INTO todos (id, title, date, position) VALUES (?, ?, ?, 0)"
        )
        .bind("old-task", "古いタスク", dateStr)
        .run();

      const res = await mf.dispatchFetch(
        "http://localhost/todos/old-task",
        {
          method: "PATCH",
          headers: JSON_HEADERS,
          body: JSON.stringify({ completed: true }),
        }
      );
      expect(res.status).toBe(403);
    });

    it("2日以上前のタスクは削除できない (403)", async () => {
      const db = await getDb();
      const twoDaysAgo = new Date();
      twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);
      const dateStr = twoDaysAgo.toISOString().slice(0, 10);

      await db
        .prepare(
          "INSERT INTO todos (id, title, date, position) VALUES (?, ?, ?, 0)"
        )
        .bind("old-task-2", "古いタスク", dateStr)
        .run();

      const res = await mf.dispatchFetch(
        "http://localhost/todos/old-task-2",
        { method: "DELETE", headers: AUTH }
      );
      expect(res.status).toBe(403);
    });

    it("1日前は editable: true", async () => {
      const d = new Date();
      d.setDate(d.getDate() - 1);
      const data = await getTodos(d.toISOString().slice(0, 10));
      expect(data.editable).toBe(true);
    });

    it("2日前は editable: false", async () => {
      const d = new Date();
      d.setDate(d.getDate() - 2);
      const data = await getTodos(d.toISOString().slice(0, 10));
      expect(data.editable).toBe(false);
    });
  });

  describe("自動繰り越し", () => {
    it("前日の未完了タスクが今日にコピーされる", async () => {
      const db = await getDb();
      const d = new Date();
      d.setDate(d.getDate() - 1);
      const dateStr = d.toISOString().slice(0, 10);

      await db.batch([
        db
          .prepare(
            "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
          )
          .bind("y1", "未完了A", dateStr, 0, 0),
        db
          .prepare(
            "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
          )
          .bind("y2", "完了済み", dateStr, 1, 1),
        db
          .prepare(
            "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
          )
          .bind("y3", "未完了B", dateStr, 2, 0),
      ]);

      const data = await getTodos();
      expect(data.todos).toHaveLength(2);
      expect(data.todos[0].title).toBe("未完了A");
      expect(data.todos[1].title).toBe("未完了B");
      expect(data.todos[0].carried_over).toBe(true);
      expect(data.todos[1].carried_over).toBe(true);
    });

    it("今日のタスクが既にあれば繰り越しは発動しない", async () => {
      const db = await getDb();
      const d = new Date();
      d.setDate(d.getDate() - 1);
      const yesterdayStr = d.toISOString().slice(0, 10);
      const todayStr = new Date().toISOString().slice(0, 10);

      await db
        .prepare(
          "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
        )
        .bind("y1", "昨日の", yesterdayStr, 0, 0)
        .run();

      await db
        .prepare(
          "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
        )
        .bind("t1", "今日の", todayStr, 0, 0)
        .run();

      const data = await getTodos();
      expect(data.todos).toHaveLength(1);
      expect(data.todos[0].title).toBe("今日の");
    });
  });
});

import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";
import { Miniflare } from "miniflare";
import * as fs from "node:fs";
import * as path from "node:path";
import { execSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { yesterday } from "../date";

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

async function createTodo(title: string, date?: string) {
  const res = await mf.dispatchFetch("http://localhost/todos", {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify(date ? { title, date } : { title }),
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

function jstDaysFromToday(offset: number): string {
  const jst = new Date(Date.now() + 9 * 60 * 60 * 1000);
  jst.setUTCDate(jst.getUTCDate() + offset);
  return jst.toISOString().slice(0, 10);
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
    await db.exec("CREATE TABLE IF NOT EXISTS carry_overs (date TEXT PRIMARY KEY, created_at TEXT NOT NULL DEFAULT (datetime('now')));");
    await db.exec("DELETE FROM todos");
    await db.exec("DELETE FROM carry_overs");
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

    it("指定した編集可能日付にタスクを追加できる", async () => {
      const dateStr = yesterday();

      const todo = await createTodo("昨日の追加", dateStr);
      expect(todo.date).toBe(dateStr);

      const data = await getTodos(dateStr);
      expect(data.todos).toHaveLength(1);
      expect(data.todos[0].title).toBe("昨日の追加");
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

  describe("冪等な作成 (client-generated id)", () => {
    const clientId = "11111111-2222-4333-8444-555555555555";

    async function postWithId(title: string) {
      return await mf.dispatchFetch("http://localhost/todos", {
        method: "POST",
        headers: JSON_HEADERS,
        body: JSON.stringify({ id: clientId, title }),
      });
    }

    it("id 付き POST は指定した id で作成される (201)", async () => {
      const res = await postWithId("移動タスク");
      expect(res.status).toBe(201);
      const todo = (await res.json()) as Record<string, unknown>;
      expect(todo.id).toBe(clientId);
    });

    it("同じ id の再送は新規作成せず既存行を 200 で返す", async () => {
      const first = await postWithId("移動タスク");
      expect(first.status).toBe(201);

      const retry = await postWithId("移動タスク");
      expect(retry.status).toBe(200);
      const todo = (await retry.json()) as Record<string, unknown>;
      expect(todo.id).toBe(clientId);
      expect(todo.title).toBe("移動タスク");

      const data = await getTodos();
      expect(data.todos).toHaveLength(1);
    });

    it("再送時は既存行の状態（完了済み等）をそのまま返す", async () => {
      await postWithId("移動タスク");
      await mf.dispatchFetch(`http://localhost/todos/${clientId}`, {
        method: "PATCH",
        headers: JSON_HEADERS,
        body: JSON.stringify({ completed: true }),
      });

      const retry = await postWithId("移動タスク");
      expect(retry.status).toBe(200);
      const todo = (await retry.json()) as Record<string, unknown>;
      expect(todo.completed).toBe(true);

      const data = await getTodos();
      expect(data.todos).toHaveLength(1);
    });

    it("UUID 形式でない id は 400", async () => {
      const res = await mf.dispatchFetch("http://localhost/todos", {
        method: "POST",
        headers: JSON_HEADERS,
        body: JSON.stringify({ id: "not-a-uuid", title: "x" }),
      });
      expect(res.status).toBe(400);
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

    it("指定した編集可能日付で reorder できる", async () => {
      const dateStr = yesterday();
      const t1 = await createTodo("昨日A", dateStr);
      const t2 = await createTodo("昨日B", dateStr);

      await mf.dispatchFetch("http://localhost/todos", {
        method: "PATCH",
        headers: JSON_HEADERS,
        body: JSON.stringify({
          date: dateStr,
          items: [
            { id: t2.id, position: 0 },
            { id: t1.id, position: 1 },
          ],
        }),
      });

      const data = await getTodos(dateStr);
      expect(data.todos.map((t) => t.title)).toEqual(["昨日B", "昨日A"]);
    });

    it("指定日のタスクに一致しない ID があれば reorder は 409", async () => {
      const yesterdayStr = yesterday();
      const t1 = await createTodo("昨日A", yesterdayStr);
      const t2 = await createTodo("今日B");

      const res = await mf.dispatchFetch("http://localhost/todos", {
        method: "PATCH",
        headers: JSON_HEADERS,
        body: JSON.stringify({
          date: yesterdayStr,
          items: [
            { id: t1.id, position: 0 },
            { id: t2.id, position: 1 },
          ],
        }),
      });
      expect(res.status).toBe(409);
    });
  });

  describe("日付制限", () => {
    it("2日以上前のタスクは更新できない (403)", async () => {
      const db = await getDb();
      const dateStr = jstDaysFromToday(-2);

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
      const dateStr = jstDaysFromToday(-2);

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

    it("2日以上前の日付には追加できない (403)", async () => {
      const dateStr = jstDaysFromToday(-2);

      const res = await mf.dispatchFetch("http://localhost/todos", {
        method: "POST",
        headers: JSON_HEADERS,
        body: JSON.stringify({ title: "古い日付", date: dateStr }),
      });
      expect(res.status).toBe(403);
    });

    it("未来日には追加できない (403)", async () => {
      const res = await mf.dispatchFetch("http://localhost/todos", {
        method: "POST",
        headers: JSON_HEADERS,
        body: JSON.stringify({ title: "未来日", date: jstDaysFromToday(1) }),
      });
      expect(res.status).toBe(403);
    });

    it("未来日では reorder できない (403)", async () => {
      const todo = await createTodo("今日のタスク");
      const res = await mf.dispatchFetch("http://localhost/todos", {
        method: "PATCH",
        headers: JSON_HEADERS,
        body: JSON.stringify({
          date: jstDaysFromToday(1),
          items: [{ id: todo.id, position: 0 }],
        }),
      });
      expect(res.status).toBe(403);
    });

    it("1日前は editable: true", async () => {
      const data = await getTodos(jstDaysFromToday(-1));
      expect(data.editable).toBe(true);
    });

    it("2日前は editable: false", async () => {
      const data = await getTodos(jstDaysFromToday(-2));
      expect(data.editable).toBe(false);
    });
  });

  describe("自動繰り越し", () => {
    it("前日の未完了タスクが今日にコピーされる", async () => {
      const db = await getDb();
      const dateStr = yesterday();

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

    it("一度繰り越した日は、二度目の GET で繰り越しが発動しない", async () => {
      const db = await getDb();
      await db
        .prepare(
          "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
        )
        .bind("y1", "昨日の", yesterday(), 0, 0)
        .run();

      const first = await getTodos();
      expect(first.todos).toHaveLength(1);
      const second = await getTodos();
      expect(second.todos).toHaveLength(1);
      expect(second.todos[0].id).toBe(first.todos[0].id);
    });

    // 回帰テスト: 「その日の todos が 0 件か」で未繰り越しを判定していた頃は、
    // 今日のタスクを全部削除すると次の GET で新しい id のまま復活していた
    // （mac / iOS 共通で「ゴミ箱を押すと消えるがリロードで戻る」と見えていた）
    it("繰り越したタスクを全部削除しても、次の GET で復活しない", async () => {
      const db = await getDb();
      await db.batch([
        db
          .prepare(
            "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
          )
          .bind("y1", "昨日A", yesterday(), 0, 0),
        db
          .prepare(
            "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
          )
          .bind("y2", "昨日B", yesterday(), 1, 0),
      ]);

      const carried = await getTodos();
      expect(carried.todos).toHaveLength(2);

      for (const todo of carried.todos) {
        const res = await mf.dispatchFetch(
          `http://localhost/todos/${todo.id}`,
          { method: "DELETE", headers: AUTH }
        );
        expect(res.status).toBe(200);
      }

      const after = await getTodos();
      expect(after.todos).toHaveLength(0);
    });

    it("繰り越したタスクを1件だけ削除しても、残りはそのまま", async () => {
      const db = await getDb();
      await db.batch([
        db
          .prepare(
            "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
          )
          .bind("y1", "昨日A", yesterday(), 0, 0),
        db
          .prepare(
            "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
          )
          .bind("y2", "昨日B", yesterday(), 1, 0),
      ]);

      const carried = await getTodos();
      const res = await mf.dispatchFetch(
        `http://localhost/todos/${carried.todos[0].id}`,
        { method: "DELETE", headers: AUTH }
      );
      expect(res.status).toBe(200);

      const after = await getTodos();
      expect(after.todos).toHaveLength(1);
      expect(after.todos[0].title).toBe("昨日B");
    });

    it("今日のタスクを全部削除した後に作り直しても、昨日の分は湧いてこない", async () => {
      const db = await getDb();
      await db
        .prepare(
          "INSERT INTO todos (id, title, date, position, completed) VALUES (?, ?, ?, ?, ?)"
        )
        .bind("y1", "昨日の", yesterday(), 0, 0)
        .run();

      const carried = await getTodos();
      await mf.dispatchFetch(`http://localhost/todos/${carried.todos[0].id}`, {
        method: "DELETE",
        headers: AUTH,
      });
      await createTodo("今日の新しいタスク");

      const after = await getTodos();
      expect(after.todos).toHaveLength(1);
      expect(after.todos[0].title).toBe("今日の新しいタスク");
    });
  });
});

describe("ウィジェットへの push", () => {
  const TOKEN = "ab".repeat(32);
  let apnsRequests: { url: string; headers: Record<string, string>; body: string }[];
  let apnsStatus: number;
  let apnsBody: string;

  beforeEach(async () => {
    apnsRequests = [];
    apnsStatus = 200;
    apnsBody = "";
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const scriptPath = buildWorker();
    mf = new Miniflare({
      modules: true,
      scriptPath,
      d1Databases: { DB: "test-db" },
      bindings: {
        API_SECRET: "test-secret",
        APNS_KEY: privateKey.export({ type: "pkcs8", format: "pem" }) as string,
        APNS_KEY_ID: "KEYID12345",
        APNS_TEAM_ID: "TEAMID1234",
      },
      compatibilityDate: "2025-04-01",
      // APNs への送信を捕まえる
      outboundService: async (req) => {
        apnsRequests.push({
          url: req.url,
          headers: Object.fromEntries(req.headers),
          body: await req.text(),
        });
        return new Response(apnsBody, { status: apnsStatus });
      },
    });

    const db = await getDb();
    await db.exec("CREATE TABLE IF NOT EXISTS todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, date TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, carried_over INTEGER NOT NULL DEFAULT 0, completed_at TEXT, duration INTEGER, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')));");
    await db.exec("CREATE TABLE IF NOT EXISTS carry_overs (date TEXT PRIMARY KEY, created_at TEXT NOT NULL DEFAULT (datetime('now')));");
    await db.exec("CREATE TABLE IF NOT EXISTS widget_push_tokens (token TEXT PRIMARY KEY, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')));");
    await db.exec("DELETE FROM todos");
    await db.exec("DELETE FROM carry_overs");
    await db.exec("DELETE FROM widget_push_tokens");
  });

  afterEach(async () => {
    await mf.dispose();
  });

  async function registerToken(token = TOKEN) {
    return mf.dispatchFetch(`http://localhost/widget-push-tokens/${token}`, {
      method: "PUT",
      headers: AUTH,
    });
  }

  // push は waitUntil で応答の後に送られるので、届くまで少し待つ
  async function waitForApns(count: number) {
    for (let i = 0; i < 50 && apnsRequests.length < count; i++) {
      await new Promise((r) => setTimeout(r, 20));
    }
  }

  async function tokenCount() {
    const row = await (await getDb())
      .prepare("SELECT COUNT(*) AS n FROM widget_push_tokens")
      .first<{ n: number }>();
    return row?.n ?? 0;
  }

  it("トークンの登録は認証が要る", async () => {
    const res = await mf.dispatchFetch(`http://localhost/widget-push-tokens/${TOKEN}`, {
      method: "PUT",
    });
    expect(res.status).toBe(401);
  });

  it("16進数でないトークンは 400", async () => {
    const res = await registerToken("not-a-token");
    expect(res.status).toBe(400);
  });

  it("同じトークンを何度登録しても1行", async () => {
    expect((await registerToken()).status).toBe(200);
    expect((await registerToken()).status).toBe(200);
    expect(await tokenCount()).toBe(1);
  });

  it("トークンを消せる", async () => {
    await registerToken();
    const res = await mf.dispatchFetch(`http://localhost/widget-push-tokens/${TOKEN}`, {
      method: "DELETE",
      headers: AUTH,
    });
    expect(res.status).toBe(200);
    expect(await tokenCount()).toBe(0);
  });

  it("タスクを作ると APNs に widgets の push を送る", async () => {
    await registerToken();
    await createTodo("Mac で足したタスク");
    await waitForApns(1);

    expect(apnsRequests).toHaveLength(1);
    const req = apnsRequests[0];
    expect(req.url).toBe(`https://api.sandbox.push.apple.com/3/device/${TOKEN}`);
    expect(req.headers["apns-push-type"]).toBe("widgets");
    expect(req.headers["apns-topic"]).toBe("com.d0ne1s.todoapp.push-type.widgets");
    expect(req.headers["authorization"]).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    expect(JSON.parse(req.body)).toEqual({ aps: { "content-changed": true } });

    const [header, payload] = req.headers["authorization"]
      .slice("bearer ".length)
      .split(".")
      .slice(0, 2)
      .map((part) => JSON.parse(Buffer.from(part, "base64url").toString()));
    expect(header).toEqual({ alg: "ES256", kid: "KEYID12345" });
    expect(payload.iss).toBe("TEAMID1234");
  });

  it("更新・削除・並べ替えでも送る", async () => {
    await registerToken();
    const todo = await createTodo("A");
    await waitForApns(1);
    await mf.dispatchFetch(`http://localhost/todos/${todo.id}`, {
      method: "PATCH",
      headers: JSON_HEADERS,
      body: JSON.stringify({ completed: true }),
    });
    await waitForApns(2);
    await mf.dispatchFetch("http://localhost/todos", {
      method: "PATCH",
      headers: JSON_HEADERS,
      body: JSON.stringify({ items: [{ id: todo.id, position: 0 }] }),
    });
    await waitForApns(3);
    await mf.dispatchFetch(`http://localhost/todos/${todo.id}`, {
      method: "DELETE",
      headers: AUTH,
    });
    await waitForApns(4);
    expect(apnsRequests).toHaveLength(4);
  });

  it("取得・失敗した書き込み・X-Skip-Widget-Push 付きの書き込みでは送らない", async () => {
    await registerToken();
    await getTodos();
    await mf.dispatchFetch("http://localhost/todos", {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({ title: "" }),
    });
    const created = await mf.dispatchFetch("http://localhost/todos", {
      method: "POST",
      headers: { ...JSON_HEADERS, "X-Skip-Widget-Push": "1" },
      body: JSON.stringify({ title: "iPhone で足したタスク" }),
    });
    expect(created.status).toBe(201);

    // 送らないことを確かめるので、送る書き込みを最後に1つ入れて、それだけが届くことを見る
    await createTodo("Mac で足したタスク");
    await waitForApns(1);
    await new Promise((r) => setTimeout(r, 200));
    expect(apnsRequests).toHaveLength(1);
  });

  it("トークンが無ければ送らない", async () => {
    await createTodo("A");
    await new Promise((r) => setTimeout(r, 200));
    expect(apnsRequests).toHaveLength(0);
  });

  it("APNs が 410 を返したトークンは消す", async () => {
    await registerToken();
    apnsStatus = 410;
    apnsBody = JSON.stringify({ reason: "Unregistered" });
    await createTodo("A");
    await waitForApns(1);
    for (let i = 0; i < 50 && (await tokenCount()) > 0; i++) {
      await new Promise((r) => setTimeout(r, 20));
    }
    expect(apnsRequests).toHaveLength(1);
    expect(await tokenCount()).toBe(0);
  });

  it("APNs が別の理由で失敗したトークンは残す", async () => {
    await registerToken();
    apnsStatus = 400;
    apnsBody = JSON.stringify({ reason: "DeviceTokenNotForTopic" });
    await createTodo("A");
    await waitForApns(1);
    await new Promise((r) => setTimeout(r, 200));
    expect(apnsRequests).toHaveLength(1);
    expect(await tokenCount()).toBe(1);
  });
});

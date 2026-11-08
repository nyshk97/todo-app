import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "./auth";
import { todos } from "./todos";
import { widgetPushTokens, notifyWidgets } from "./widgetPush";

type Bindings = {
  DB: D1Database;
  API_SECRET: string;
  APNS_KEY?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_HOST?: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.use(
  "/todos/*",
  cors({
    origin: ["https://todo-shelf-web.pages.dev"],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
  })
);
app.use(
  "/todos",
  cors({
    origin: ["https://todo-shelf-web.pages.dev"],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
  })
);

app.get("/", (c) => c.json({ status: "ok" }));

app.use("/todos/*", auth);
app.use("/todos", auth);

// タスクの書き込みが成功したら iOS ウィジェットに読み直しを促す。
// iOS アプリ自身の書き込みはアプリがその場でウィジェットを読み直すので、
// X-Skip-Widget-Push で省く（push も iOS の予算を食うため）。
// "/todos" と "/todos/*" の2つに付けると二重に走り得るので、1つのミドルウェアでパスを見る
app.use("*", async (c, next) => {
  await next();
  const path = c.req.path;
  if (path !== "/todos" && !path.startsWith("/todos/")) return;
  if (c.req.method === "GET" || c.req.method === "OPTIONS") return;
  if (!c.res.ok || c.req.header("X-Skip-Widget-Push")) return;
  c.executionCtx.waitUntil(
    notifyWidgets(c.env).catch((e) =>
      console.log(JSON.stringify({ widgetPush: "error", message: String(e) }))
    )
  );
});

app.route("/todos", todos);

app.use("/widget-push-tokens/*", auth);
app.route("/widget-push-tokens", widgetPushTokens);

export default app;

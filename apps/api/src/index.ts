import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "./auth";
import { todos } from "./todos";

type Bindings = {
  DB: D1Database;
  API_SECRET: string;
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
app.route("/todos", todos);

export default app;

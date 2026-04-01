import { Hono } from "hono";
import { auth } from "./auth";
import { todos } from "./todos";

type Bindings = {
  DB: D1Database;
  API_SECRET: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.get("/", (c) => c.json({ status: "ok" }));

app.use("/todos/*", auth);
app.use("/todos", auth);
app.route("/todos", todos);

export default app;

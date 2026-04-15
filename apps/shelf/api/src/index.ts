import { Hono } from "hono";
import type { Bindings } from "./lib/db";
import { auth } from "./middleware/auth";
import projects from "./routes/projects";
import sections from "./routes/sections";
import tasks from "./routes/tasks";
import comments from "./routes/comments";

const app = new Hono<{ Bindings: Bindings }>();

app.get("/", (c) => c.json({ status: "ok" }));

app.use("/projects/*", auth);
app.use("/sections/*", auth);
app.use("/tasks/*", auth);
app.use("/comments/*", auth);

app.route("/", projects);
app.route("/", sections);
app.route("/", tasks);
app.route("/", comments);

export default app;

import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Bindings } from "./lib/db";
import { auth } from "./middleware/auth";
import projects from "./routes/projects";
import sections from "./routes/sections";
import tasks from "./routes/tasks";
import comments from "./routes/comments";
import attachments from "./routes/attachments";

const app = new Hono<{ Bindings: Bindings }>();

app.use("*", cors());

app.get("/", (c) => c.json({ status: "ok" }));

app.use("/projects/*", auth);
app.use("/sections/*", auth);
app.use("/tasks/*", auth);
app.use("/comments/*", auth);
app.use("/attachments/*", auth);

app.route("/", projects);
app.route("/", sections);
app.route("/", tasks);
app.route("/", comments);
app.route("/", attachments);

export default app;

import { Hono } from "hono";
import type { Bindings } from "../lib/db";

const app = new Hono<{ Bindings: Bindings }>();

// GET /attachments/:id
app.get("/attachments/:id", async (c) => {
  const id = c.req.param("id");
  const row = await c.env.DB.prepare(
    "SELECT r2_key, content_type, filename FROM attachments WHERE id = ?"
  )
    .bind(id)
    .first<{ r2_key: string; content_type: string; filename: string }>();
  if (!row) return c.json({ error: "Not found" }, 404);

  const object = await c.env.ATTACHMENTS.get(row.r2_key);
  if (!object) return c.json({ error: "File not found in storage" }, 404);

  c.header("Content-Type", row.content_type);
  c.header(
    "Content-Disposition",
    `inline; filename="${encodeURIComponent(row.filename)}"`
  );
  c.header("Cache-Control", "private, max-age=3600");
  return c.body(object.body as ReadableStream);
});

// DELETE /attachments/:id
app.delete("/attachments/:id", async (c) => {
  const id = c.req.param("id");
  const row = await c.env.DB.prepare(
    "SELECT r2_key FROM attachments WHERE id = ?"
  )
    .bind(id)
    .first<{ r2_key: string }>();
  if (!row) return c.json({ error: "Not found" }, 404);

  await c.env.ATTACHMENTS.delete(row.r2_key);
  await c.env.DB.prepare("DELETE FROM attachments WHERE id = ?")
    .bind(id)
    .run();
  return c.body(null, 204);
});

export default app;

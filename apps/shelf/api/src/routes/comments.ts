import { Hono } from "hono";
import type { Bindings } from "../lib/db";
import { generateId, nowJST, buildUpdate } from "../lib/db";

const MAX_FILES = 5;
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB

const app = new Hono<{ Bindings: Bindings }>();

// GET /tasks/:id/comments
app.get("/tasks/:id/comments", async (c) => {
  const taskId = c.req.param("id");
  const comments = await c.env.DB.prepare(
    "SELECT * FROM comments WHERE task_id = ? ORDER BY created_at"
  )
    .bind(taskId)
    .all();

  const commentIds = comments.results.map((c: Record<string, unknown>) => c.id as string);
  let attachmentsByComment: Record<string, Record<string, unknown>[]> = {};

  if (commentIds.length > 0) {
    const placeholders = commentIds.map(() => "?").join(",");
    const attachments = await c.env.DB.prepare(
      `SELECT id, comment_id, filename, content_type, size, created_at FROM attachments WHERE comment_id IN (${placeholders}) ORDER BY created_at`
    )
      .bind(...commentIds)
      .all();

    for (const a of attachments.results) {
      const commentId = a.comment_id as string;
      if (!attachmentsByComment[commentId]) attachmentsByComment[commentId] = [];
      attachmentsByComment[commentId].push(a);
    }
  }

  const result = comments.results.map((comment: Record<string, unknown>) => ({
    ...comment,
    attachments: attachmentsByComment[comment.id as string] ?? [],
  }));

  return c.json(result);
});

// POST /tasks/:id/comments (multipart)
app.post("/tasks/:id/comments", async (c) => {
  const taskId = c.req.param("id");
  const formData = await c.req.formData();

  const content = (formData.get("content") as string) ?? "";
  const files = formData.getAll("files") as File[];

  if (!content && files.length === 0) {
    return c.json({ error: "content or files required" }, 400);
  }
  if (files.length > MAX_FILES) {
    return c.json({ error: `Maximum ${MAX_FILES} files allowed` }, 400);
  }
  for (const file of files) {
    if (file.size > MAX_FILE_SIZE) {
      return c.json({ error: `File ${file.name} exceeds 10MB limit` }, 400);
    }
  }

  const commentId = generateId();
  const now = nowJST();

  await c.env.DB.prepare(
    "INSERT INTO comments (id, task_id, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?)"
  )
    .bind(commentId, taskId, content, now, now)
    .run();

  // Upload files to R2 and insert attachment records
  const attachments: Record<string, unknown>[] = [];
  for (const file of files) {
    const attachmentId = generateId();
    const r2Key = `${taskId}/${commentId}/${attachmentId}_${file.name}`;

    await c.env.ATTACHMENTS.put(r2Key, file.stream(), {
      httpMetadata: { contentType: file.type },
    });

    await c.env.DB.prepare(
      "INSERT INTO attachments (id, comment_id, filename, content_type, size, r2_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
    )
      .bind(attachmentId, commentId, file.name, file.type, file.size, r2Key, now)
      .run();

    attachments.push({
      id: attachmentId,
      comment_id: commentId,
      filename: file.name,
      content_type: file.type,
      size: file.size,
      created_at: now,
    });
  }

  const comment = await c.env.DB.prepare(
    "SELECT * FROM comments WHERE id = ?"
  )
    .bind(commentId)
    .first();

  return c.json({ ...comment, attachments }, 201);
});

// PATCH /comments/:id
app.patch("/comments/:id", async (c) => {
  const id = c.req.param("id");
  const body = await c.req.json<{ content: string }>();

  const existing = await c.env.DB.prepare(
    "SELECT id FROM comments WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!existing) return c.json({ error: "Not found" }, 404);

  const { sql, bindings } = buildUpdate(
    "comments",
    id,
    { content: body.content },
    nowJST()
  );
  await c.env.DB.prepare(sql).bind(...bindings).run();

  const comment = await c.env.DB.prepare(
    "SELECT * FROM comments WHERE id = ?"
  )
    .bind(id)
    .first();

  // Fetch attachments for this comment
  const attachments = await c.env.DB.prepare(
    "SELECT id, comment_id, filename, content_type, size, created_at FROM attachments WHERE comment_id = ? ORDER BY created_at"
  )
    .bind(id)
    .all();

  return c.json({ ...comment, attachments: attachments.results });
});

// DELETE /comments/:id
app.delete("/comments/:id", async (c) => {
  const id = c.req.param("id");

  // Get attachments to delete from R2
  const attachments = await c.env.DB.prepare(
    "SELECT r2_key FROM attachments WHERE comment_id = ?"
  )
    .bind(id)
    .all();

  if (attachments.results.length === 0) {
    const existing = await c.env.DB.prepare(
      "SELECT id FROM comments WHERE id = ?"
    )
      .bind(id)
      .first();
    if (!existing) return c.json({ error: "Not found" }, 404);
  }

  // Delete R2 objects
  for (const a of attachments.results) {
    await c.env.ATTACHMENTS.delete(a.r2_key as string);
  }

  await c.env.DB.prepare("DELETE FROM comments WHERE id = ?").bind(id).run();
  return c.body(null, 204);
});

export default app;

CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  comment_id TEXT NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  filename TEXT NOT NULL,
  content_type TEXT NOT NULL,
  size INTEGER NOT NULL,
  r2_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_attachments_comment_id ON attachments(comment_id);

ALTER TABLE tasks ADD COLUMN archived_at TEXT;

CREATE INDEX idx_tasks_archived_at ON tasks(archived_at);

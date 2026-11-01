-- 繰り返しタスク（Recurring プロジェクトのタスクだけが持つ）
-- repeat_unit: 'day' | 'week' | 'month' | 'year'
-- repeat_anchor_day: 月・年ごとのときの元の「何日」。1/31 の毎月が 2/28 → 3/31 と戻れるように覚えておく
ALTER TABLE tasks ADD COLUMN repeat_unit TEXT;
ALTER TABLE tasks ADD COLUMN repeat_interval INTEGER;
ALTER TABLE tasks ADD COLUMN repeat_anchor_day INTEGER;

INSERT INTO projects (id, name, position, created_at, updated_at)
SELECT
  lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (random() & 3), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))),
  'Recurring',
  (SELECT COALESCE(MAX(position), -1) + 1 FROM projects),
  datetime('now', '+9 hours'),
  datetime('now', '+9 hours')
WHERE NOT EXISTS (SELECT 1 FROM projects WHERE name = 'Recurring');

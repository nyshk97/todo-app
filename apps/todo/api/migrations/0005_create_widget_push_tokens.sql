-- iOS ウィジェットの WidgetKit push のトークン。
-- タスクが書き換わったら、ここにあるトークンへ「中身が変わった」を送り、
-- Mac や shelf で変えた分もウィジェットが読み直すようにする。
CREATE TABLE widget_push_tokens (
  token TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

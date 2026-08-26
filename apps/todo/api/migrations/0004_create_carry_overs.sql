-- 繰り越し済みの日付を記録するマーカー。
-- 以前は「その日の todos が 0 件かどうか」で未繰り越しを判定していたため、
-- その日のタスクを全部削除すると再度繰り越しが走り、削除したタスクが
-- 新しい id で復活していた。
CREATE TABLE carry_overs (
  date TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 既存データの初期投入: すでに todos が存在する日付は繰り越し済みとみなす。
-- これをしないと、過去分・当日分が次の GET で再繰り越しされる。
INSERT OR IGNORE INTO carry_overs (date) SELECT DISTINCT date FROM todos;

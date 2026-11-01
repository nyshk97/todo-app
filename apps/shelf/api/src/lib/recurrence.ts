import type { RepeatUnit } from "@todo-shelf/shared";
import type { Bindings } from "./db";
import { nowJST } from "./db";

export const RECURRING_PROJECT_NAME = "Recurring";
const MAIN_PROJECT_NAME = "Shelf";

const REPEAT_UNITS: readonly RepeatUnit[] = ["day", "week", "month", "year"];
export const MAX_REPEAT_INTERVAL = 999;

export function isRepeatUnit(value: unknown): value is RepeatUnit {
  return typeof value === "string" && (REPEAT_UNITS as readonly string[]).includes(value);
}

export function isRepeatInterval(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 1 &&
    value <= MAX_REPEAT_INTERVAL
  );
}

export function dayOfMonth(date: string): number {
  return Number(date.slice(8, 10));
}

function format(y: number, m: number, d: number): string {
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

function addDays(date: string, days: number): string {
  const [y, m, d] = date.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return format(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

/** 月を足す。日は anchorDay をその月の末日で頭打ちにする（1/31 + 1か月 = 2/28、その次は 3/31） */
function addMonths(date: string, months: number, anchorDay: number): string {
  const [y, m] = date.split("-").map(Number);
  const index = y * 12 + (m - 1) + months;
  const ny = Math.floor(index / 12);
  const nm = (index % 12) + 1;
  const lastDay = new Date(Date.UTC(ny, nm, 0)).getUTCDate();
  return format(ny, nm, Math.min(anchorDay, lastDay));
}

export function nextOccurrence(
  date: string,
  unit: RepeatUnit,
  interval: number,
  anchorDay: number | null
): string {
  const anchor = anchorDay ?? dayOfMonth(date);
  switch (unit) {
    case "day":
      return addDays(date, interval);
    case "week":
      return addDays(date, interval * 7);
    case "month":
      return addMonths(date, interval, anchor);
    case "year":
      return addMonths(date, interval * 12, anchor);
  }
}

/** seed から決定的に UUID を導出する（cron の再実行でも同じ回の複製が1件に収まるように） */
export async function deterministicId(seed: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(seed));
  const b = new Uint8Array(digest).slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

type RecurringTask = {
  id: string;
  title: string;
  due_date: string;
  repeat_unit: RepeatUnit;
  repeat_interval: number;
  repeat_anchor_day: number | null;
};

type CommentRow = { id: string; content: string; created_at: string; updated_at: string };
type AttachmentRow = {
  id: string;
  comment_id: string;
  filename: string;
  content_type: string;
  size: number;
  r2_key: string;
  created_at: string;
};

export type MaterializeResult = {
  created: { sourceId: string; copyId: string; dueDate: string; nextDueDate: string }[];
};

/**
 * 期日が today 以前の Recurring のタスクを、Shelf のセクションなしの先頭に複製し、
 * 元のタスクの期日を today より後の回へ進める。毎朝の cron から呼ぶ。
 *
 * - 複製の期日は today（取りこぼした回でも「今日やること」として入れる）。何回分か取りこぼしていても
 *   複製は1件で、次回は today より後まで進める
 * - 1件失敗しても残りは続ける（失敗したものは期日が進まないので、翌朝もう一度試す）
 * - 前の回の複製が Shelf に残っていても、回ごとに別の行として入れる
 * - コメントと添付も写す。添付は R2 の実体もコピーし、複製を消しても元の添付が消えないようにする
 * - 複製・コメント・添付の id は (元のタスク, 回の日付) から決めるので、再実行しても増えない
 */
export async function materializeRecurring(
  env: Bindings,
  today: string
): Promise<MaterializeResult> {
  const result: MaterializeResult = { created: [] };
  const db = env.DB;

  const main = await db
    .prepare("SELECT id FROM projects WHERE name = ?")
    .bind(MAIN_PROJECT_NAME)
    .first<{ id: string }>();
  const recurring = await db
    .prepare("SELECT id FROM projects WHERE name = ?")
    .bind(RECURRING_PROJECT_NAME)
    .first<{ id: string }>();
  if (!main || !recurring) {
    console.error(
      JSON.stringify({ recurring: "skip", reason: "project not found", hasMain: !!main, hasRecurring: !!recurring })
    );
    return result;
  }

  const due = await db
    .prepare(
      `SELECT id, title, due_date, repeat_unit, repeat_interval, repeat_anchor_day
       FROM tasks
       WHERE project_id = ? AND archived_at IS NULL
         AND repeat_unit IS NOT NULL AND repeat_interval IS NOT NULL
         AND due_date IS NOT NULL AND due_date <= ?
       ORDER BY due_date, position`
    )
    .bind(recurring.id, today)
    .all<RecurringTask>();

  for (const task of due.results) {
    if (!isRepeatUnit(task.repeat_unit) || !isRepeatInterval(task.repeat_interval)) continue;
    const putKeys: string[] = [];
    try {
      let next = task.due_date;
      while (next <= today) {
        next = nextOccurrence(next, task.repeat_unit, task.repeat_interval, task.repeat_anchor_day);
      }

      const copyId = await deterministicId(`recurring:${task.id}:${task.due_date}`);
      const now = nowJST();

      const comments = await db
        .prepare("SELECT id, content, created_at, updated_at FROM comments WHERE task_id = ? ORDER BY created_at")
        .bind(task.id)
        .all<CommentRow>();
      const attachments = comments.results.length
        ? await db
            .prepare(
              `SELECT a.* FROM attachments a JOIN comments c ON a.comment_id = c.id
               WHERE c.task_id = ? ORDER BY a.created_at`
            )
            .bind(task.id)
            .all<AttachmentRow>()
        : { results: [] as AttachmentRow[] };

      const stmts: D1PreparedStatement[] = [
        db
          .prepare(
            `INSERT OR IGNORE INTO tasks (id, project_id, section_id, title, due_date, position, created_at, updated_at)
             SELECT ?, ?, NULL, ?, ?, COALESCE(MIN(position), 0) - 1, ?, ?
             FROM tasks WHERE project_id = ? AND section_id IS NULL AND archived_at IS NULL`
          )
          .bind(copyId, main.id, task.title, today, now, now, main.id),
      ];

      const commentIds = new Map<string, string>();
      for (const comment of comments.results) {
        const commentId = await deterministicId(`recurring:${copyId}:comment:${comment.id}`);
        commentIds.set(comment.id, commentId);
        stmts.push(
          db
            .prepare(
              "INSERT OR IGNORE INTO comments (id, task_id, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?)"
            )
            .bind(commentId, copyId, comment.content, comment.created_at, comment.updated_at)
        );
      }

      for (const a of attachments.results) {
        const commentId = commentIds.get(a.comment_id);
        if (!commentId) continue;
        const object = await env.ATTACHMENTS.get(a.r2_key);
        if (!object) continue;
        const attachmentId = await deterministicId(`recurring:${copyId}:attachment:${a.id}`);
        const r2Key = `${copyId}/${commentId}/${attachmentId}_${a.filename}`;
        await env.ATTACHMENTS.put(r2Key, object.body, { httpMetadata: { contentType: a.content_type } });
        putKeys.push(r2Key);
        stmts.push(
          db
            .prepare(
              "INSERT OR IGNORE INTO attachments (id, comment_id, filename, content_type, size, r2_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
            )
            .bind(attachmentId, commentId, a.filename, a.content_type, a.size, r2Key, a.created_at)
        );
      }

      // 期日が読んだときのままのときだけ進める（同時に走った別の実行が先に進めていたら何もしない）
      stmts.push(
        db
          .prepare("UPDATE tasks SET due_date = ?, updated_at = ? WHERE id = ? AND due_date = ?")
          .bind(next, now, task.id, task.due_date)
      );

      await db.batch(stmts);
      result.created.push({ sourceId: task.id, copyId, dueDate: task.due_date, nextDueDate: next });
    } catch (e) {
      // batch まで届かなかった添付のコピーは持ち主がいないので消す
      await Promise.allSettled(putKeys.map((key) => env.ATTACHMENTS.delete(key)));
      console.error(JSON.stringify({ recurring: "error", sourceId: task.id, dueDate: task.due_date, error: String(e) }));
    }
  }

  console.log(JSON.stringify({ recurring: "done", today, created: result.created.length }));
  return result;
}

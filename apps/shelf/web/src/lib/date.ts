export function todayJST(): string {
  return new Date(Date.now() + 9 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

export type DueDateStatus = "overdue" | "today" | "soon" | "normal" | null;

/**
 * 期日の状態を判定する
 * - 過ぎている → "overdue" (赤)
 * - 当日 → "today" (オレンジ)
 * - 1〜3日後 → "soon" (黄)
 * - それ以外 → "normal"
 */
export function getDueDateStatus(dueDate: string | null): DueDateStatus {
  if (!dueDate) return null;
  const today = todayJST();
  const diff = (new Date(dueDate).getTime() - new Date(today).getTime()) / 86400000;
  if (diff < 0) return "overdue";
  if (diff === 0) return "today";
  if (diff <= 3) return "soon";
  return "normal";
}

export function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
}

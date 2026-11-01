import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { Task } from "@todo-shelf/shared";
import { api } from "../lib/api";
import { formatDate } from "../lib/date";
import { repeatLabel } from "../lib/recurrence";
import { AddTask } from "./AddTask";
import { useToast } from "./Toast";

interface RecurringViewProps {
  projectId: string;
  onClickTask: (task: Task) => void;
}

/** 期日が未設定のものを先頭に、あとは次の期日の順 */
function compareTasks(a: Task, b: Task): number {
  if (a.due_date === b.due_date) return a.position - b.position;
  if (!a.due_date) return -1;
  if (!b.due_date) return 1;
  return a.due_date < b.due_date ? -1 : 1;
}

function groupLabel(task: Task): string {
  if (!task.due_date) return "期日未設定";
  const [y, m] = task.due_date.split("-").map(Number);
  return `${y}年${m}月`;
}

const repeatIcon = (
  <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2.5 6.5h9l-2.5-2.5M13.5 9.5h-9l2.5 2.5" />
  </svg>
);

export function RecurringView({ projectId, onClickTask }: RecurringViewProps) {
  const queryClient = useQueryClient();
  const { showToast } = useToast();
  const { data } = useQuery({
    queryKey: ["tasks", projectId],
    queryFn: () => api.get<Task[]>(`/projects/${projectId}/tasks`),
  });

  const handleAdd = async (title: string) => {
    try {
      const task = await api.post<Task>("/tasks", { title, project_id: projectId });
      await queryClient.invalidateQueries({ queryKey: ["tasks", projectId] });
      // 期日と繰り返しを続けて入れられるように詳細を開く
      onClickTask(task);
    } catch {
      showToast("タスクの作成に失敗しました", () => handleAdd(title));
    }
  };

  if (data === undefined) {
    return (
      <div style={{ padding: 64, textAlign: "center", color: "var(--text-quaternary)" }}>
        読み込み中...
      </div>
    );
  }

  const tasks = [...data].sort(compareTasks);
  const groups: { label: string; tasks: Task[] }[] = [];
  for (const task of tasks) {
    const label = groupLabel(task);
    const last = groups[groups.length - 1];
    if (last?.label === label) last.tasks.push(task);
    else groups.push({ label, tasks: [task] });
  }

  return (
    <div style={{ padding: "16px 0 96px" }}>
      <div style={{ fontSize: 12, color: "var(--text-quaternary)", padding: "0 12px", marginBottom: 8, lineHeight: 1.6 }}>
        期日の朝5時に、Shelfの先頭へ複製されます（ここの期日は次の回へ進みます）
      </div>

      <AddTask onAdd={handleAdd} />

      {tasks.length === 0 && (
        <div style={{ padding: 48, textAlign: "center", color: "var(--text-quaternary)", fontSize: 13 }}>
          繰り返しのタスクはありません
        </div>
      )}

      {groups.map((group) => (
        <div key={group.label} style={{ marginTop: 12 }}>
          <div style={{
            fontSize: 12,
            fontWeight: 590,
            color: "var(--text-tertiary)",
            padding: "8px 12px 6px",
            borderBottom: "1px solid var(--border-subtle)",
          }}>
            {group.label}
          </div>
          {group.tasks.map((task) => {
            const hasRepeat = task.repeat_unit !== null && task.repeat_interval !== null;
            return (
              <div
                key={task.id}
                onClick={() => onClickTask(task)}
                style={{
                  display: "flex",
                  alignItems: "flex-start",
                  gap: 8,
                  padding: "10px 12px",
                  borderBottom: "1px solid var(--border-subtle)",
                  cursor: "pointer",
                  transition: "background 0.1s",
                }}
                onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.03)")}
                onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
              >
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, color: "var(--text-secondary)" }}>{task.title}</div>
                  <div style={{ display: "flex", gap: 10, marginTop: 3, fontSize: 11, color: "var(--text-quaternary)" }}>
                    {task.due_date && <span>{formatDate(task.due_date)}</span>}
                    {hasRepeat ? (
                      <span style={{ display: "inline-flex", alignItems: "center", gap: 3 }}>
                        {repeatIcon}
                        {repeatLabel(task.repeat_unit!, task.repeat_interval!)}
                      </span>
                    ) : (
                      <span style={{ color: "var(--color-orange)" }}>繰り返し未設定</span>
                    )}
                  </div>
                </div>
                {task.comment_count > 0 && (
                  <span style={{ fontSize: 11, color: "var(--text-quaternary)", whiteSpace: "nowrap" }}>
                    💬 {task.comment_count}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

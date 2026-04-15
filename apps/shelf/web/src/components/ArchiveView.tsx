import { useEffect, useState } from "react";
import type { ArchivedTask, Project, Section } from "@todo-shelf/shared";
import { api } from "../lib/api";
import { TaskDetail } from "./TaskDetail";

interface ArchiveViewProps {
  projects: Project[];
  sections: Section[];
}

export function ArchiveView({ projects, sections }: ArchiveViewProps) {
  const [tasks, setTasks] = useState<ArchivedTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedTask, setSelectedTask] = useState<ArchivedTask | null>(null);

  const loadTasks = async () => {
    setLoading(true);
    const data = await api.get<ArchivedTask[]>("/tasks/archived");
    setTasks(data);
    setLoading(false);
  };

  useEffect(() => {
    loadTasks();
  }, []);

  const handleRestore = async (id: string) => {
    await api.post(`/tasks/${id}/restore`, {});
    setTasks((prev) => prev.filter((t) => t.id !== id));
    setSelectedTask(null);
  };

  const handleDelete = async (id: string) => {
    await api.delete(`/tasks/${id}`);
    setTasks((prev) => prev.filter((t) => t.id !== id));
    setSelectedTask(null);
  };

  if (loading) {
    return (
      <div style={{ padding: 64, textAlign: "center", color: "var(--text-quaternary)" }}>
        読み込み中...
      </div>
    );
  }

  if (tasks.length === 0) {
    return (
      <div style={{ padding: 64, textAlign: "center", color: "var(--text-quaternary)" }}>
        アーカイブされたタスクはありません
      </div>
    );
  }

  return (
    <div style={{ padding: "16px 0" }}>
      <div style={{ fontSize: 13, color: "var(--text-quaternary)", marginBottom: 12 }}>
        {tasks.length} 件のアーカイブ
      </div>

      {tasks.map((task) => (
        <div
          key={task.id}
          onClick={() => setSelectedTask(task)}
          style={{
            padding: "10px 12px",
            borderBottom: "1px solid var(--border-subtle)",
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            gap: 8,
          }}
        >
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{
              fontSize: 14,
              color: "var(--text-secondary)",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}>
              {task.title}
            </div>
            <div style={{ fontSize: 11, color: "var(--text-quaternary)", marginTop: 2, display: "flex", gap: 8 }}>
              <span>{task.project_name}</span>
              {task.archived_at && (
                <span>移動: {task.archived_at.slice(0, 10)}</span>
              )}
              {task.comment_count > 0 && (
                <span>💬 {task.comment_count}</span>
              )}
            </div>
          </div>
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleRestore(task.id);
            }}
            style={{
              padding: "4px 10px",
              borderRadius: "var(--radius-md)",
              border: "1px solid var(--border-standard)",
              background: "rgba(255,255,255,0.02)",
              color: "var(--accent-bright)",
              fontSize: 11,
              fontWeight: 510,
              flexShrink: 0,
            }}
          >
            戻す
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleDelete(task.id);
            }}
            style={{
              padding: "4px 8px",
              borderRadius: "var(--radius-md)",
              border: "none",
              background: "transparent",
              color: "var(--text-quaternary)",
              fontSize: 11,
              flexShrink: 0,
            }}
          >
            削除
          </button>
        </div>
      ))}

      {selectedTask && (
        <TaskDetail
          task={selectedTask}
          projects={projects}
          sections={sections}
          onUpdate={() => {}}
          onDelete={handleDelete}
          onMoveToToday={() => {}}
          onClose={() => setSelectedTask(null)}
          readOnly
        />
      )}
    </div>
  );
}

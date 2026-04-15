import { useState } from "react";
import type { Task } from "@todo-shelf/shared";
import { getDueDateStatus, formatDate } from "../lib/date";

interface TaskItemProps {
  task: Task;
  onDelete: (id: string) => void;
  onClick: (task: Task) => void;
}

const dueDateColors: Record<string, string> = {
  overdue: "var(--color-red)",
  soon: "var(--color-orange)",
  normal: "var(--text-quaternary)",
};

export function TaskItem({ task, onDelete, onClick }: TaskItemProps) {
  const [showConfirm, setShowConfirm] = useState(false);
  const status = getDueDateStatus(task.due_date);

  return (
    <div
      onClick={() => onClick(task)}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: "8px 12px",
        borderRadius: "var(--radius-sm)",
        cursor: "pointer",
        transition: "background 0.1s",
      }}
      onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.03)")}
      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
    >
      <span style={{ flex: 1, fontSize: 14, color: "var(--text-secondary)" }}>
        {task.title}
      </span>

      {task.due_date && status && (
        <span style={{
          fontSize: 11,
          fontWeight: 510,
          color: dueDateColors[status],
          whiteSpace: "nowrap",
        }}>
          {formatDate(task.due_date)}
        </span>
      )}

      {showConfirm ? (
        <span
          style={{ display: "flex", gap: 4 }}
          onClick={(e) => e.stopPropagation()}
        >
          <button
            onClick={() => onDelete(task.id)}
            style={{
              padding: "2px 8px",
              borderRadius: "var(--radius-sm)",
              border: "none",
              background: "var(--color-red)",
              color: "#fff",
              fontSize: 11,
              fontWeight: 510,
            }}
          >
            削除
          </button>
          <button
            onClick={() => setShowConfirm(false)}
            style={{
              padding: "2px 8px",
              borderRadius: "var(--radius-sm)",
              border: "1px solid var(--border-standard)",
              background: "transparent",
              color: "var(--text-tertiary)",
              fontSize: 11,
            }}
          >
            戻す
          </button>
        </span>
      ) : (
        <button
          onClick={(e) => {
            e.stopPropagation();
            setShowConfirm(true);
          }}
          style={{
            padding: "2px 6px",
            borderRadius: "var(--radius-sm)",
            border: "none",
            background: "transparent",
            color: "var(--text-quaternary)",
            fontSize: 12,
            opacity: 0,
            transition: "opacity 0.1s",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.opacity = "1")}
          className="delete-btn"
        >
          ×
        </button>
      )}
    </div>
  );
}

import { useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
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

  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: `task-${task.id}` });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={{
        ...style,
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: "8px 12px",
        borderRadius: "var(--radius-sm)",
        cursor: "pointer",
        transition: "background 0.1s",
      }}
      onClick={() => onClick(task)}
      onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.03)")}
      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
    >
      <span
        {...attributes}
        {...listeners}
        onClick={(e) => e.stopPropagation()}
        style={{
          cursor: "grab",
          color: "var(--text-quaternary)",
          fontSize: 10,
          padding: "2px 2px",
          userSelect: "none",
          touchAction: "none",
        }}
      >
        ⠿
      </span>

      <span style={{ flex: 1, fontSize: 14, color: "var(--text-secondary)" }}>
        {task.title}
      </span>

      {task.comment_count > 0 && (
        <span style={{
          fontSize: 11,
          color: "var(--text-quaternary)",
          display: "flex",
          alignItems: "center",
          gap: 3,
        }}>
          <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor">
            <path d="M2.5 2A1.5 1.5 0 001 3.5v7A1.5 1.5 0 002.5 12H5l3 3 3-3h2.5a1.5 1.5 0 001.5-1.5v-7A1.5 1.5 0 0013.5 2h-11zM2.5 3h11a.5.5 0 01.5.5v7a.5.5 0 01-.5.5H10.7L8 13.2 5.3 11H2.5a.5.5 0 01-.5-.5v-7a.5.5 0 01.5-.5z"/>
          </svg>
          {task.comment_count}
        </span>
      )}

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
        >
          ×
        </button>
      )}
    </div>
  );
}

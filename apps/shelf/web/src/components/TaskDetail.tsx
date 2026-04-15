import { useEffect, useState } from "react";
import type { Task, Comment, Project, Section } from "@todo-shelf/shared";
import { api } from "../lib/api";
import { getDueDateStatus } from "../lib/date";
import { AutoLink } from "./AutoLink";

interface TaskDetailProps {
  task: Task;
  projects: Project[];
  sections: Section[];
  onUpdate: (task: Task) => void;
  onDelete: (id: string) => void;
  onMoveToToday: (id: string) => void;
  onClose: () => void;
}

const dueDateColors: Record<string, string> = {
  overdue: "var(--color-red)",
  soon: "var(--color-orange)",
  normal: "var(--text-quaternary)",
};

export function TaskDetail({
  task,
  projects,
  sections,
  onUpdate,
  onDelete,
  onMoveToToday,
  onClose,
}: TaskDetailProps) {
  const [title, setTitle] = useState(task.title);
  const [dueDate, setDueDate] = useState(task.due_date ?? "");
  const [comments, setComments] = useState<Comment[]>([]);
  const [newComment, setNewComment] = useState("");
  const [editingCommentId, setEditingCommentId] = useState<string | null>(null);
  const [editingCommentText, setEditingCommentText] = useState("");
  const [showMoveUI, setShowMoveUI] = useState(false);

  useEffect(() => {
    api.get<Comment[]>(`/tasks/${task.id}/comments`).then(setComments);
  }, [task.id]);

  const handleTitleBlur = async () => {
    const trimmed = title.trim();
    if (trimmed && trimmed !== task.title) {
      const updated = await api.patch<Task>(`/tasks/${task.id}`, { title: trimmed });
      onUpdate(updated);
    }
  };

  const handleDueDateChange = async (value: string) => {
    setDueDate(value);
    const updated = await api.patch<Task>(`/tasks/${task.id}`, {
      due_date: value || null,
    });
    onUpdate(updated);
  };

  const handleAddComment = async () => {
    const trimmed = newComment.trim();
    if (!trimmed) return;
    const comment = await api.post<Comment>(`/tasks/${task.id}/comments`, {
      content: trimmed,
    });
    setComments((prev) => [...prev, comment]);
    setNewComment("");
  };

  const handleUpdateComment = async (id: string) => {
    const trimmed = editingCommentText.trim();
    if (!trimmed) return;
    const updated = await api.patch<Comment>(`/comments/${id}`, {
      content: trimmed,
    });
    setComments((prev) => prev.map((c) => (c.id === id ? updated : c)));
    setEditingCommentId(null);
  };

  const handleDeleteComment = async (id: string) => {
    await api.delete(`/comments/${id}`);
    setComments((prev) => prev.filter((c) => c.id !== id));
  };

  const handleMove = async (projectId: string, sectionId: string | null) => {
    const updated = await api.patch<Task>(`/tasks/${task.id}`, {
      project_id: projectId,
      section_id: sectionId,
    });
    onUpdate(updated);
    setShowMoveUI(false);
    onClose();
  };

  const status = getDueDateStatus(task.due_date);

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.85)",
        display: "flex",
        justifyContent: "center",
        alignItems: "flex-start",
        paddingTop: 80,
        zIndex: 100,
      }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: 520,
          maxHeight: "80vh",
          overflow: "auto",
          background: "var(--bg-surface)",
          border: "1px solid var(--border-standard)",
          borderRadius: 12,
          padding: 24,
        }}
      >
        {/* Title */}
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onBlur={handleTitleBlur}
          onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}
          style={{
            width: "100%",
            background: "transparent",
            border: "none",
            color: "var(--text-primary)",
            fontSize: 20,
            fontWeight: 590,
            letterSpacing: "-0.24px",
            outline: "none",
            marginBottom: 16,
          }}
        />

        {/* Due date */}
        <div style={{ marginBottom: 16, display: "flex", alignItems: "center", gap: 8 }}>
          <label style={{ fontSize: 13, fontWeight: 510, color: "var(--text-tertiary)" }}>
            期日
          </label>
          <input
            type="date"
            value={dueDate}
            onChange={(e) => handleDueDateChange(e.target.value)}
            style={{
              background: "rgba(255,255,255,0.02)",
              border: "1px solid var(--border-standard)",
              borderRadius: "var(--radius-md)",
              color: status ? dueDateColors[status] : "var(--text-secondary)",
              padding: "4px 8px",
              fontSize: 13,
              outline: "none",
            }}
          />
          {dueDate && (
            <button
              onClick={() => handleDueDateChange("")}
              style={{
                background: "transparent",
                border: "none",
                color: "var(--text-quaternary)",
                fontSize: 12,
              }}
            >
              クリア
            </button>
          )}
        </div>

        {/* Actions */}
        <div style={{
          display: "flex",
          gap: 8,
          marginBottom: 20,
          paddingBottom: 16,
          borderBottom: "1px solid var(--border-subtle)",
        }}>
          <button
            onClick={() => setShowMoveUI(!showMoveUI)}
            style={{
              padding: "4px 10px",
              borderRadius: "var(--radius-md)",
              border: "1px solid var(--border-standard)",
              background: "rgba(255,255,255,0.02)",
              color: "var(--text-secondary)",
              fontSize: 12,
              fontWeight: 510,
            }}
          >
            移動
          </button>
          <button
            onClick={() => onMoveToToday(task.id)}
            style={{
              padding: "4px 10px",
              borderRadius: "var(--radius-md)",
              border: "1px solid var(--border-standard)",
              background: "rgba(255,255,255,0.02)",
              color: "var(--accent-bright)",
              fontSize: 12,
              fontWeight: 510,
            }}
          >
            今日のTODOへ移動
          </button>
          <button
            onClick={() => { onDelete(task.id); onClose(); }}
            style={{
              marginLeft: "auto",
              padding: "4px 10px",
              borderRadius: "var(--radius-md)",
              border: "none",
              background: "transparent",
              color: "var(--color-red)",
              fontSize: 12,
              fontWeight: 510,
            }}
          >
            削除
          </button>
        </div>

        {/* Move UI */}
        {showMoveUI && (
          <div style={{
            marginBottom: 16,
            padding: 12,
            background: "rgba(255,255,255,0.02)",
            borderRadius: "var(--radius-lg)",
            border: "1px solid var(--border-subtle)",
          }}>
            <div style={{ fontSize: 12, fontWeight: 510, color: "var(--text-tertiary)", marginBottom: 8 }}>
              移動先を選択
            </div>
            {projects.map((p) => (
              <div key={p.id} style={{ marginBottom: 8 }}>
                <button
                  onClick={() => handleMove(p.id, null)}
                  style={{
                    display: "block",
                    width: "100%",
                    textAlign: "left",
                    padding: "4px 8px",
                    borderRadius: "var(--radius-sm)",
                    border: "none",
                    background: p.id === task.project_id ? "rgba(255,255,255,0.05)" : "transparent",
                    color: "var(--text-secondary)",
                    fontSize: 13,
                    fontWeight: 510,
                  }}
                >
                  {p.name}（セクションなし）
                </button>
                {sections
                  .filter((s) => s.project_id === p.id)
                  .map((s) => (
                    <button
                      key={s.id}
                      onClick={() => handleMove(p.id, s.id)}
                      style={{
                        display: "block",
                        width: "100%",
                        textAlign: "left",
                        padding: "4px 8px 4px 20px",
                        borderRadius: "var(--radius-sm)",
                        border: "none",
                        background: s.id === task.section_id ? "rgba(255,255,255,0.05)" : "transparent",
                        color: "var(--text-tertiary)",
                        fontSize: 13,
                      }}
                    >
                      {s.name}
                    </button>
                  ))}
              </div>
            ))}
          </div>
        )}

        {/* Comments */}
        <div>
          <div style={{ fontSize: 13, fontWeight: 510, color: "var(--text-tertiary)", marginBottom: 8 }}>
            コメント
          </div>

          {comments.map((c) => (
            <div
              key={c.id}
              style={{
                padding: "8px 0",
                borderBottom: "1px solid var(--border-subtle)",
              }}
            >
              {editingCommentId === c.id ? (
                <div>
                  <textarea
                    value={editingCommentText}
                    onChange={(e) => setEditingCommentText(e.target.value)}
                    style={{
                      width: "100%",
                      minHeight: 60,
                      background: "rgba(255,255,255,0.02)",
                      border: "1px solid var(--border-standard)",
                      borderRadius: "var(--radius-sm)",
                      color: "var(--text-secondary)",
                      padding: "6px 8px",
                      fontSize: 13,
                      resize: "vertical",
                      outline: "none",
                    }}
                  />
                  <div style={{ display: "flex", gap: 4, marginTop: 4 }}>
                    <button
                      onClick={() => handleUpdateComment(c.id)}
                      style={{
                        padding: "2px 8px",
                        borderRadius: "var(--radius-sm)",
                        border: "none",
                        background: "var(--accent)",
                        color: "#fff",
                        fontSize: 11,
                        fontWeight: 510,
                      }}
                    >
                      保存
                    </button>
                    <button
                      onClick={() => setEditingCommentId(null)}
                      style={{
                        padding: "2px 8px",
                        borderRadius: "var(--radius-sm)",
                        border: "1px solid var(--border-standard)",
                        background: "transparent",
                        color: "var(--text-tertiary)",
                        fontSize: 11,
                      }}
                    >
                      キャンセル
                    </button>
                  </div>
                </div>
              ) : (
                <div style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
                  <div style={{ flex: 1, fontSize: 14, color: "var(--text-secondary)", whiteSpace: "pre-wrap" }}>
                    <AutoLink text={c.content} />
                  </div>
                  <div style={{ display: "flex", gap: 4, flexShrink: 0 }}>
                    <button
                      onClick={() => { setEditingCommentId(c.id); setEditingCommentText(c.content); }}
                      style={{
                        padding: "1px 6px",
                        borderRadius: "var(--radius-sm)",
                        border: "none",
                        background: "transparent",
                        color: "var(--text-quaternary)",
                        fontSize: 11,
                      }}
                    >
                      編集
                    </button>
                    <button
                      onClick={() => handleDeleteComment(c.id)}
                      style={{
                        padding: "1px 6px",
                        borderRadius: "var(--radius-sm)",
                        border: "none",
                        background: "transparent",
                        color: "var(--text-quaternary)",
                        fontSize: 11,
                      }}
                    >
                      削除
                    </button>
                  </div>
                </div>
              )}
            </div>
          ))}

          {/* Add comment */}
          <div style={{ marginTop: 12, display: "flex", gap: 8 }}>
            <input
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); handleAddComment(); } }}
              placeholder="コメントを追加..."
              style={{
                flex: 1,
                background: "rgba(255,255,255,0.02)",
                border: "1px solid var(--border-standard)",
                borderRadius: "var(--radius-sm)",
                color: "var(--text-secondary)",
                padding: "6px 8px",
                fontSize: 13,
                outline: "none",
              }}
            />
            <button
              onClick={handleAddComment}
              disabled={!newComment.trim()}
              style={{
                padding: "4px 12px",
                borderRadius: "var(--radius-md)",
                border: "none",
                background: newComment.trim() ? "var(--accent)" : "rgba(255,255,255,0.02)",
                color: newComment.trim() ? "#fff" : "var(--text-quaternary)",
                fontSize: 12,
                fontWeight: 510,
              }}
            >
              送信
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

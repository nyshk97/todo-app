import { useEffect, useState, useRef } from "react";
import type { Task, Comment, Project, Section, Attachment } from "@todo-shelf/shared";
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
  readOnly?: boolean;
}

const dueDateColors: Record<string, string> = {
  overdue: "var(--color-red)",
  soon: "var(--color-orange)",
  normal: "var(--text-quaternary)",
};

function isImageType(contentType: string) {
  return contentType.startsWith("image/");
}

function formatFileSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function TaskDetail({
  task,
  projects,
  sections,
  onUpdate,
  onDelete,
  onMoveToToday,
  onClose,
  readOnly = false,
}: TaskDetailProps) {
  const [title, setTitle] = useState(task.title);
  const [dueDate, setDueDate] = useState(task.due_date ?? "");
  const [comments, setComments] = useState<Comment[]>([]);
  const [newComment, setNewComment] = useState("");
  const [pendingFiles, setPendingFiles] = useState<File[]>([]);
  const [editingCommentId, setEditingCommentId] = useState<string | null>(null);
  const [editingCommentText, setEditingCommentText] = useState("");
  const [showMoveUI, setShowMoveUI] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

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
    if (!trimmed && pendingFiles.length === 0) return;
    setSubmitting(true);

    const formData = new FormData();
    formData.append("content", trimmed);
    for (const file of pendingFiles) {
      formData.append("files", file);
    }

    const comment = await api.postForm<Comment>(`/tasks/${task.id}/comments`, formData);
    setComments((prev) => [...prev, comment]);
    setNewComment("");
    setPendingFiles([]);
    setSubmitting(false);
    onUpdate({ ...task, comment_count: task.comment_count + 1 });
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    setPendingFiles((prev) => [...prev, ...files].slice(0, 5));
    e.target.value = "";
  };

  const removePendingFile = (index: number) => {
    setPendingFiles((prev) => prev.filter((_, i) => i !== index));
  };

  const handleDeleteAttachment = async (commentId: string, attachmentId: string) => {
    await api.delete(`/attachments/${attachmentId}`);
    setComments((prev) =>
      prev.map((c) =>
        c.id === commentId
          ? { ...c, attachments: c.attachments.filter((a) => a.id !== attachmentId) }
          : c
      )
    );
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
    onUpdate({ ...task, comment_count: task.comment_count - 1 });
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
        {readOnly ? (
          <div style={{
            fontSize: 20,
            fontWeight: 590,
            letterSpacing: "-0.24px",
            color: "var(--text-primary)",
            marginBottom: 16,
          }}>
            {task.title}
          </div>
        ) : (
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onBlur={handleTitleBlur}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) e.currentTarget.blur(); }}
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
        )}

        {/* Due date */}
        <div style={{ marginBottom: 16, display: "flex", alignItems: "center", gap: 8 }}>
          <label style={{ fontSize: 13, fontWeight: 510, color: "var(--text-tertiary)" }}>
            期日
          </label>
          {readOnly ? (
            <span style={{
              fontSize: 13,
              color: status ? dueDateColors[status] : "var(--text-secondary)",
            }}>
              {dueDate || "未設定"}
            </span>
          ) : (
            <>
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
            </>
          )}
        </div>

        {/* Actions */}
        {!readOnly && (
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
        )}

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
                <div>
                  <div style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
                    <div style={{ flex: 1, fontSize: 14, color: "var(--text-secondary)", whiteSpace: "pre-wrap" }}>
                      {c.content && <AutoLink text={c.content} />}
                    </div>
                    {!readOnly && (
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
                    )}
                  </div>

                  {/* Attachments */}
                  {c.attachments && c.attachments.length > 0 && (
                    <div style={{ marginTop: 8, display: "flex", flexDirection: "column", gap: 6 }}>
                      {c.attachments.map((a: Attachment) => (
                        <div key={a.id} style={{ position: "relative" }}>
                          {isImageType(a.content_type) ? (
                            <a href={api.attachmentUrl(a.id)} target="_blank" rel="noopener noreferrer">
                              <img
                                src={api.attachmentUrl(a.id)}
                                alt={a.filename}
                                style={{
                                  maxWidth: "100%",
                                  maxHeight: 300,
                                  borderRadius: "var(--radius-sm)",
                                  border: "1px solid var(--border-subtle)",
                                }}
                              />
                            </a>
                          ) : (
                            <a
                              href={api.attachmentUrl(a.id)}
                              target="_blank"
                              rel="noopener noreferrer"
                              style={{
                                display: "flex",
                                alignItems: "center",
                                gap: 6,
                                padding: "6px 10px",
                                background: "rgba(255,255,255,0.02)",
                                border: "1px solid var(--border-subtle)",
                                borderRadius: "var(--radius-sm)",
                                color: "var(--accent-bright)",
                                fontSize: 12,
                                textDecoration: "none",
                              }}
                            >
                              <span>📎</span>
                              <span>{a.filename}</span>
                              <span style={{ color: "var(--text-quaternary)", fontSize: 11 }}>
                                ({formatFileSize(a.size)})
                              </span>
                            </a>
                          )}
                          {!readOnly && (
                            <button
                              onClick={() => handleDeleteAttachment(c.id, a.id)}
                              style={{
                                position: "absolute",
                                top: 4,
                                right: 4,
                                padding: "2px 6px",
                                borderRadius: "var(--radius-sm)",
                                border: "none",
                                background: "rgba(0,0,0,0.6)",
                                color: "var(--text-quaternary)",
                                fontSize: 10,
                                cursor: "pointer",
                              }}
                            >
                              ✕
                            </button>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          ))}

          {/* Add comment */}
          {!readOnly && (
            <div style={{ marginTop: 12 }}>
              {/* Pending files preview */}
              {pendingFiles.length > 0 && (
                <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 8 }}>
                  {pendingFiles.map((file, i) => (
                    <div key={i} style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 4,
                      padding: "3px 8px",
                      background: "rgba(255,255,255,0.04)",
                      border: "1px solid var(--border-subtle)",
                      borderRadius: "var(--radius-sm)",
                      fontSize: 11,
                      color: "var(--text-tertiary)",
                    }}>
                      <span>{file.name}</span>
                      <button
                        onClick={() => removePendingFile(i)}
                        style={{
                          background: "transparent",
                          border: "none",
                          color: "var(--text-quaternary)",
                          fontSize: 10,
                          padding: "0 2px",
                          cursor: "pointer",
                        }}
                      >
                        ✕
                      </button>
                    </div>
                  ))}
                </div>
              )}

              <div style={{ display: "flex", gap: 8 }}>
                <input
                  ref={fileInputRef}
                  type="file"
                  multiple
                  style={{ display: "none" }}
                  onChange={handleFileSelect}
                />
                <button
                  onClick={() => fileInputRef.current?.click()}
                  disabled={pendingFiles.length >= 5}
                  style={{
                    padding: "6px 8px",
                    borderRadius: "var(--radius-sm)",
                    border: "1px solid var(--border-standard)",
                    background: "rgba(255,255,255,0.02)",
                    color: pendingFiles.length >= 5 ? "var(--text-quaternary)" : "var(--text-tertiary)",
                    fontSize: 14,
                    cursor: pendingFiles.length >= 5 ? "default" : "pointer",
                  }}
                  title="ファイルを添付"
                >
                  📎
                </button>
                <textarea
                  value={newComment}
                  onChange={(e) => {
                    setNewComment(e.target.value);
                    e.target.style.height = "auto";
                    e.target.style.height = Math.min(e.target.scrollHeight, 120) + "px";
                  }}
                  onKeyDown={(e) => { if (e.key === "Enter" && e.metaKey && !e.nativeEvent.isComposing) { e.preventDefault(); handleAddComment(); } }}
                  placeholder="コメントを追加...（⌘+Enter で送信）"
                  rows={1}
                  style={{
                    flex: 1,
                    background: "rgba(255,255,255,0.02)",
                    border: "1px solid var(--border-standard)",
                    borderRadius: "var(--radius-sm)",
                    color: "var(--text-secondary)",
                    padding: "6px 8px",
                    fontSize: 13,
                    outline: "none",
                    resize: "none",
                    overflow: "hidden",
                    fontFamily: "inherit",
                    lineHeight: "1.5",
                  }}
                />
                <button
                  onClick={handleAddComment}
                  disabled={(!newComment.trim() && pendingFiles.length === 0) || submitting}
                  style={{
                    padding: "4px 12px",
                    borderRadius: "var(--radius-md)",
                    border: "none",
                    background: (newComment.trim() || pendingFiles.length > 0) ? "var(--accent)" : "rgba(255,255,255,0.02)",
                    color: (newComment.trim() || pendingFiles.length > 0) ? "#fff" : "var(--text-quaternary)",
                    fontSize: 12,
                    fontWeight: 510,
                  }}
                >
                  送信
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

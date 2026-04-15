import { useState } from "react";

interface AddTaskProps {
  onAdd: (title: string) => void;
}

export function AddTask({ onAdd }: AddTaskProps) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState("");

  const handleSubmit = () => {
    const trimmed = title.trim();
    if (trimmed) {
      onAdd(trimmed);
      setTitle("");
      // keep editing mode open for rapid entry
    }
  };

  if (!editing) {
    return (
      <button
        onClick={() => setEditing(true)}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 6,
          width: "100%",
          padding: "6px 12px",
          border: "none",
          borderRadius: "var(--radius-sm)",
          background: "transparent",
          color: "var(--text-quaternary)",
          fontSize: 13,
          textAlign: "left",
          transition: "color 0.1s",
        }}
        onMouseEnter={(e) => (e.currentTarget.style.color = "var(--text-tertiary)")}
        onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-quaternary)")}
      >
        <span style={{ fontSize: 15 }}>＋</span> タスクを追加
      </button>
    );
  }

  return (
    <div style={{ padding: "4px 12px" }}>
      <input
        autoFocus
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.nativeEvent.isComposing) handleSubmit();
          if (e.key === "Escape") { setEditing(false); setTitle(""); }
        }}
        onBlur={() => {
          if (!title.trim()) { setEditing(false); setTitle(""); }
        }}
        placeholder="タスク名を入力..."
        style={{
          width: "100%",
          padding: "6px 8px",
          borderRadius: "var(--radius-sm)",
          border: "1px solid var(--border-standard)",
          background: "rgba(255,255,255,0.02)",
          color: "var(--text-primary)",
          fontSize: 14,
          outline: "none",
        }}
      />
    </div>
  );
}

import { useState } from "react";
import type { Project } from "@todo-shelf/shared";
import { api } from "../lib/api";

interface TabNavProps {
  projects: Project[];
  activeId: string | null;
  upcomingCount: number;
  onSelect: (id: string) => void;
  onProjectsChange: (projects: Project[]) => void;
}

export function TabNav({ projects, activeId, upcomingCount, onSelect, onProjectsChange }: TabNavProps) {
  const [showMenu, setShowMenu] = useState(false);
  const [addingName, setAddingName] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingName, setEditingName] = useState("");

  const handleAdd = async () => {
    const trimmed = addingName.trim();
    if (!trimmed) return;
    const p = await api.post<Project>("/projects", { name: trimmed });
    onProjectsChange([...projects, p]);
    setAddingName("");
    onSelect(p.id);
  };

  const handleRename = async (id: string) => {
    const trimmed = editingName.trim();
    if (!trimmed || trimmed === projects.find((p) => p.id === id)?.name) {
      setEditingId(null);
      return;
    }
    const updated = await api.patch<Project>(`/projects/${id}`, { name: trimmed });
    onProjectsChange(projects.map((p) => (p.id === id ? updated : p)));
    setEditingId(null);
  };

  const handleDelete = async (id: string) => {
    await api.delete(`/projects/${id}`);
    const remaining = projects.filter((p) => p.id !== id);
    onProjectsChange(remaining);
    if (activeId === id && remaining.length > 0) {
      onSelect(remaining[0].id);
    }
  };

  return (
    <nav style={{
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 2,
      padding: "12px 16px",
      borderBottom: "1px solid var(--border-subtle)",
      background: "var(--bg-panel)",
      position: "relative",
    }}>
      {projects.map((p) => (
        <button
          key={p.id}
          onClick={() => onSelect(p.id)}
          onDoubleClick={() => { setEditingId(p.id); setEditingName(p.name); }}
          style={{
            padding: "8px 20px",
            borderRadius: "var(--radius-md)",
            border: "none",
            background: activeId === p.id ? "rgba(255,255,255,0.1)" : "transparent",
            color: activeId === p.id ? "var(--text-primary)" : "var(--text-tertiary)",
            fontSize: 14,
            fontWeight: activeId === p.id ? 600 : 510,
            transition: "all 0.15s",
            cursor: "pointer",
          }}
        >
          {p.name}
        </button>
      ))}

      <button
        onClick={() => onSelect("__archive__")}
        style={{
          padding: "8px 20px",
          borderRadius: "var(--radius-md)",
          border: "none",
          background: activeId === "__archive__" ? "rgba(255,255,255,0.1)" : "transparent",
          color: activeId === "__archive__" ? "var(--text-primary)" : "var(--text-tertiary)",
          fontSize: 14,
          fontWeight: activeId === "__archive__" ? 600 : 510,
          transition: "all 0.15s",
          cursor: "pointer",
        }}
      >
        Archive
      </button>

      <button
        onClick={() => setShowMenu(!showMenu)}
        style={{
          padding: "4px 8px",
          borderRadius: "var(--radius-md)",
          border: "none",
          background: "transparent",
          color: "var(--text-quaternary)",
          fontSize: 14,
          transition: "color 0.1s",
          cursor: "pointer",
        }}
        onMouseEnter={(e) => (e.currentTarget.style.color = "var(--text-tertiary)")}
        onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-quaternary)")}
      >
        ⚙
      </button>

      {upcomingCount > 0 && (
        <span style={{
          position: "absolute",
          right: 16,
          padding: "2px 8px",
          borderRadius: 9999,
          background: "var(--color-orange)",
          color: "#000",
          fontSize: 11,
          fontWeight: 590,
        }}>
          期限近い: {upcomingCount}
        </span>
      )}

      {/* Project management dropdown */}
      {showMenu && (
        <div
          style={{
            position: "absolute",
            top: "100%",
            left: 16,
            marginTop: 4,
            background: "var(--bg-surface)",
            border: "1px solid var(--border-standard)",
            borderRadius: "var(--radius-lg)",
            padding: 8,
            minWidth: 220,
            zIndex: 50,
          }}
        >
          <div style={{ fontSize: 12, fontWeight: 510, color: "var(--text-tertiary)", padding: "4px 8px", marginBottom: 4 }}>
            プロジェクト管理
          </div>

          {projects.map((p) => (
            <div key={p.id} style={{ display: "flex", alignItems: "center", gap: 4, padding: "2px 0" }}>
              {editingId === p.id ? (
                <input
                  autoFocus
                  value={editingName}
                  onChange={(e) => setEditingName(e.target.value)}
                  onBlur={() => handleRename(p.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleRename(p.id);
                    if (e.key === "Escape") setEditingId(null);
                  }}
                  style={{
                    flex: 1,
                    background: "rgba(255,255,255,0.02)",
                    border: "1px solid var(--border-standard)",
                    borderRadius: "var(--radius-sm)",
                    color: "var(--text-primary)",
                    padding: "2px 6px",
                    fontSize: 13,
                    outline: "none",
                  }}
                />
              ) : (
                <span
                  style={{ flex: 1, fontSize: 13, color: "var(--text-secondary)", padding: "2px 8px" }}
                  onDoubleClick={() => { setEditingId(p.id); setEditingName(p.name); }}
                >
                  {p.name}
                </span>
              )}
              <button
                onClick={() => { setEditingId(p.id); setEditingName(p.name); }}
                style={{
                  background: "transparent",
                  border: "none",
                  color: "var(--text-quaternary)",
                  fontSize: 11,
                  padding: "2px 4px",
                }}
              >
                編集
              </button>
              <button
                onClick={() => handleDelete(p.id)}
                style={{
                  background: "transparent",
                  border: "none",
                  color: "var(--color-red)",
                  fontSize: 11,
                  padding: "2px 4px",
                }}
              >
                削除
              </button>
            </div>
          ))}

          <div style={{ borderTop: "1px solid var(--border-subtle)", marginTop: 4, paddingTop: 4, display: "flex", gap: 4 }}>
            <input
              value={addingName}
              onChange={(e) => setAddingName(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") handleAdd(); }}
              placeholder="新規プロジェクト..."
              style={{
                flex: 1,
                background: "rgba(255,255,255,0.02)",
                border: "1px solid var(--border-standard)",
                borderRadius: "var(--radius-sm)",
                color: "var(--text-primary)",
                padding: "4px 8px",
                fontSize: 12,
                outline: "none",
              }}
            />
            <button
              onClick={handleAdd}
              disabled={!addingName.trim()}
              style={{
                padding: "4px 8px",
                borderRadius: "var(--radius-sm)",
                border: "none",
                background: addingName.trim() ? "var(--accent)" : "rgba(255,255,255,0.02)",
                color: addingName.trim() ? "#fff" : "var(--text-quaternary)",
                fontSize: 11,
                fontWeight: 510,
              }}
            >
              追加
            </button>
          </div>
        </div>
      )}

      {/* Backdrop to close menu */}
      {showMenu && (
        <div
          style={{ position: "fixed", inset: 0, zIndex: 49 }}
          onClick={() => setShowMenu(false)}
        />
      )}
    </nav>
  );
}

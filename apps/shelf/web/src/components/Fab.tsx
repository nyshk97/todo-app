import { useState } from "react";
import type { Project } from "@todo-shelf/shared";
import { api } from "../lib/api";

interface FabProps {
  projects: Project[];
  backlogUpcomingCount: number;
  onNavigate: (path: string) => void;
  onProjectsChange: (projects: Project[]) => void;
}

export function Fab({ projects, backlogUpcomingCount, onNavigate, onProjectsChange }: FabProps) {
  const [showMenu, setShowMenu] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [addingName, setAddingName] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingName, setEditingName] = useState("");

  const backlogProject = projects.find((p) => p.name === "Backlog");
  const archivePath = "/archive";

  const handleAdd = async () => {
    const trimmed = addingName.trim();
    if (!trimmed) return;
    const p = await api.post<Project>("/projects", { name: trimmed });
    onProjectsChange([...projects, p]);
    setAddingName("");
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
    onProjectsChange(projects.filter((p) => p.id !== id));
  };

  return (
    <>
      {/* FAB button */}
      <button
        onClick={() => { setShowMenu(!showMenu); setShowSettings(false); }}
        style={{
          position: "fixed",
          bottom: 24,
          right: 24,
          width: 48,
          height: 48,
          borderRadius: "50%",
          border: "none",
          background: "var(--bg-elevated)",
          color: "var(--text-secondary)",
          fontSize: 20,
          fontWeight: 700,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          cursor: "pointer",
          boxShadow: "0 2px 12px rgba(0,0,0,0.4)",
          transition: "background 0.15s, transform 0.15s",
          zIndex: 100,
        }}
        onMouseEnter={(e) => (e.currentTarget.style.background = "var(--bg-surface)")}
        onMouseLeave={(e) => (e.currentTarget.style.background = "var(--bg-elevated)")}
      >
        •••
        {backlogUpcomingCount > 0 && (
          <span style={{
            position: "absolute",
            top: -2,
            right: -2,
            minWidth: 18,
            height: 18,
            borderRadius: 9,
            background: "var(--color-orange)",
            color: "#000",
            fontSize: 11,
            fontWeight: 600,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: "0 4px",
          }}>
            {backlogUpcomingCount}
          </span>
        )}
      </button>

      {/* Backdrop */}
      {showMenu && (
        <div
          style={{ position: "fixed", inset: 0, zIndex: 99 }}
          onClick={() => { setShowMenu(false); setShowSettings(false); }}
        />
      )}

      {/* Menu */}
      {showMenu && (
        <div style={{
          position: "fixed",
          bottom: 80,
          right: 24,
          background: "var(--bg-surface)",
          border: "1px solid var(--border-standard)",
          borderRadius: "var(--radius-lg)",
          padding: 4,
          minWidth: 180,
          zIndex: 101,
          boxShadow: "0 4px 16px rgba(0,0,0,0.3)",
        }}>
          {/* Backlog */}
          {backlogProject && (
            <button
              onClick={() => {
                onNavigate(`/projects/${backlogProject.id}`);
                setShowMenu(false);
              }}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                width: "100%",
                padding: "8px 12px",
                borderRadius: "var(--radius-md)",
                border: "none",
                background: "transparent",
                color: "var(--text-secondary)",
                fontSize: 13,
                fontWeight: 510,
                cursor: "pointer",
                textAlign: "left",
                transition: "background 0.1s",
              }}
              onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.05)")}
              onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
            >
              Backlog
              {backlogUpcomingCount > 0 && (
                <span style={{
                  marginLeft: "auto",
                  minWidth: 18,
                  height: 18,
                  borderRadius: 9,
                  background: "var(--color-orange)",
                  color: "#000",
                  fontSize: 11,
                  fontWeight: 600,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  padding: "0 4px",
                }}>
                  {backlogUpcomingCount}
                </span>
              )}
            </button>
          )}

          {/* Archive */}
          <button
            onClick={() => {
              onNavigate(archivePath);
              setShowMenu(false);
            }}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              width: "100%",
              padding: "8px 12px",
              borderRadius: "var(--radius-md)",
              border: "none",
              background: "transparent",
              color: "var(--text-secondary)",
              fontSize: 13,
              fontWeight: 510,
              cursor: "pointer",
              textAlign: "left",
              transition: "background 0.1s",
            }}
            onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.05)")}
            onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
          >
            Archive
          </button>

          {/* Divider */}
          <div style={{ borderTop: "1px solid var(--border-subtle)", margin: "4px 0" }} />

          {/* Settings toggle */}
          <button
            onClick={() => setShowSettings(!showSettings)}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              width: "100%",
              padding: "8px 12px",
              borderRadius: "var(--radius-md)",
              border: "none",
              background: showSettings ? "rgba(255,255,255,0.05)" : "transparent",
              color: "var(--text-tertiary)",
              fontSize: 13,
              fontWeight: 510,
              cursor: "pointer",
              textAlign: "left",
              transition: "background 0.1s",
            }}
            onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.05)")}
            onMouseLeave={(e) => {
              if (!showSettings) e.currentTarget.style.background = "transparent";
            }}
          >
            設定
          </button>

          {/* Settings panel (inline) */}
          {showSettings && (
            <div style={{ padding: "4px 8px 8px" }}>
              <div style={{
                fontSize: 11,
                fontWeight: 510,
                color: "var(--text-quaternary)",
                padding: "4px 4px 4px",
                marginBottom: 2,
              }}>
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
                        fontSize: 12,
                        outline: "none",
                      }}
                    />
                  ) : (
                    <span style={{ flex: 1, fontSize: 12, color: "var(--text-secondary)", padding: "2px 4px" }}>
                      {p.name}
                    </span>
                  )}
                  <button
                    onClick={() => { setEditingId(p.id); setEditingName(p.name); }}
                    style={{
                      background: "transparent",
                      border: "none",
                      color: "var(--text-quaternary)",
                      fontSize: 10,
                      padding: "2px 4px",
                      cursor: "pointer",
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
                      fontSize: 10,
                      padding: "2px 4px",
                      cursor: "pointer",
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
                  onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) handleAdd(); }}
                  placeholder="新規プロジェクト..."
                  style={{
                    flex: 1,
                    background: "rgba(255,255,255,0.02)",
                    border: "1px solid var(--border-standard)",
                    borderRadius: "var(--radius-sm)",
                    color: "var(--text-primary)",
                    padding: "3px 6px",
                    fontSize: 11,
                    outline: "none",
                  }}
                />
                <button
                  onClick={handleAdd}
                  disabled={!addingName.trim()}
                  style={{
                    padding: "3px 6px",
                    borderRadius: "var(--radius-sm)",
                    border: "none",
                    background: addingName.trim() ? "var(--accent)" : "rgba(255,255,255,0.02)",
                    color: addingName.trim() ? "#fff" : "var(--text-quaternary)",
                    fontSize: 10,
                    fontWeight: 510,
                    cursor: "pointer",
                  }}
                >
                  追加
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </>
  );
}

import type { Project } from "@todo-shelf/shared";

interface TabNavProps {
  projects: Project[];
  activeId: string | null;
  upcomingCount: number;
  onSelect: (id: string) => void;
}

export function TabNav({ projects, activeId, upcomingCount, onSelect }: TabNavProps) {
  return (
    <nav style={{
      display: "flex",
      alignItems: "center",
      gap: 4,
      padding: "8px 16px",
      borderBottom: "1px solid var(--border-subtle)",
      background: "var(--bg-panel)",
    }}>
      {projects.map((p) => (
        <button
          key={p.id}
          onClick={() => onSelect(p.id)}
          style={{
            padding: "6px 14px",
            borderRadius: "var(--radius-md)",
            border: "none",
            background: activeId === p.id ? "rgba(255,255,255,0.08)" : "transparent",
            color: activeId === p.id ? "var(--text-primary)" : "var(--text-tertiary)",
            fontSize: 13,
            fontWeight: 510,
            transition: "all 0.15s",
          }}
        >
          {p.name}
        </button>
      ))}
      {upcomingCount > 0 && (
        <span style={{
          marginLeft: "auto",
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
    </nav>
  );
}

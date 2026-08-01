import { useNavigate } from "react-router-dom";

interface HeaderProps {
  title: string;
  backTo?: string;
  backLabel?: string;
}

export function Header({ title, backTo, backLabel }: HeaderProps) {
  const navigate = useNavigate();

  return (
    <header style={{
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: "12px 16px",
      borderBottom: "1px solid var(--border-subtle)",
      background: "var(--bg-panel)",
    }}>
      {backTo && (
        <button
          onClick={() => navigate(backTo)}
          style={{
            display: "flex",
            alignItems: "center",
            gap: 4,
            padding: "4px 8px",
            borderRadius: "var(--radius-md)",
            border: "none",
            background: "transparent",
            color: "var(--text-tertiary)",
            fontSize: 13,
            fontWeight: 510,
            cursor: "pointer",
            transition: "color 0.1s",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.color = "var(--text-secondary)")}
          onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-tertiary)")}
        >
          ← {backLabel ?? "戻る"}
        </button>
      )}
      <span style={{
        fontSize: 15,
        fontWeight: 600,
        color: "var(--text-primary)",
      }}>
        {title}
      </span>
    </header>
  );
}

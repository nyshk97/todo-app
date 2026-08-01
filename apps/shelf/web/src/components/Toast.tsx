import { useState, useEffect, useCallback, createContext, useContext, type ReactNode } from "react";

interface ToastItem {
  id: number;
  message: string;
  onRetry?: () => void;
}

interface ToastContextValue {
  showToast: (message: string, onRetry?: () => void) => void;
}

const ToastContext = createContext<ToastContextValue>({ showToast: () => {} });

export function useToast() {
  return useContext(ToastContext);
}

let nextId = 0;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const showToast = useCallback((message: string, onRetry?: () => void) => {
    const id = nextId++;
    setToasts((prev) => [...prev, { id, message, onRetry }]);
  }, []);

  const dismiss = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return (
    <ToastContext.Provider value={{ showToast }}>
      {children}
      <div style={{
        position: "fixed",
        bottom: 20,
        left: "50%",
        transform: "translateX(-50%)",
        display: "flex",
        flexDirection: "column",
        gap: 8,
        zIndex: 9999,
      }}>
        {toasts.map((t) => (
          <ToastItem key={t.id} toast={t} onDismiss={dismiss} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function ToastItem({ toast, onDismiss }: { toast: ToastItem; onDismiss: (id: number) => void }) {
  useEffect(() => {
    const timer = setTimeout(() => onDismiss(toast.id), 5000);
    return () => clearTimeout(timer);
  }, [toast.id, onDismiss]);

  return (
    <div style={{
      background: "var(--bg-elevated)",
      border: "1px solid var(--border-standard)",
      borderRadius: "var(--radius-md)",
      padding: "8px 12px",
      display: "flex",
      alignItems: "center",
      gap: 10,
      boxShadow: "0 4px 12px rgba(0,0,0,0.4)",
      minWidth: 240,
    }}>
      <span style={{ fontSize: 13, color: "var(--color-red)", flex: 1 }}>
        {toast.message}
      </span>
      {toast.onRetry && (
        <button
          onClick={() => {
            onDismiss(toast.id);
            toast.onRetry?.();
          }}
          style={{
            padding: "3px 10px",
            borderRadius: "var(--radius-sm)",
            border: "1px solid var(--border-standard)",
            background: "rgba(255,255,255,0.04)",
            color: "var(--accent-bright)",
            fontSize: 12,
            fontWeight: 510,
            whiteSpace: "nowrap",
            cursor: "pointer",
          }}
        >
          再試行
        </button>
      )}
      <button
        onClick={() => onDismiss(toast.id)}
        style={{
          background: "transparent",
          border: "none",
          color: "var(--text-quaternary)",
          fontSize: 14,
          cursor: "pointer",
          padding: "0 2px",
        }}
      >
        ✕
      </button>
    </div>
  );
}

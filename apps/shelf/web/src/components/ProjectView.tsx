import { useEffect, useState, useCallback } from "react";
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  verticalListSortingStrategy,
  arrayMove,
} from "@dnd-kit/sortable";
import type { Section, Task } from "@todo-shelf/shared";
import { api } from "../lib/api";
import { SectionView } from "./SectionView";

interface ProjectViewProps {
  projectId: string;
  onClickTask: (task: Task) => void;
}

export function ProjectView({ projectId, onClickTask }: ProjectViewProps) {
  const [sections, setSections] = useState<Section[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [addingSectionName, setAddingSectionName] = useState("");
  const [showAddSection, setShowAddSection] = useState(false);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
  );

  const load = useCallback(async () => {
    const [s, t] = await Promise.all([
      api.get<Section[]>(`/projects/${projectId}/sections`),
      api.get<Task[]>(`/projects/${projectId}/tasks`),
    ]);
    setSections(s);
    setTasks(t);
    setLoading(false);
  }, [projectId]);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  const handleAddTask = async (title: string, sectionId: string | null) => {
    const task = await api.post<Task>("/tasks", {
      title,
      project_id: projectId,
      section_id: sectionId,
    });
    setTasks((prev) => [...prev, task]);
  };

  const handleDeleteTask = async (id: string) => {
    await api.delete(`/tasks/${id}`);
    setTasks((prev) => prev.filter((t) => t.id !== id));
  };

  const handleReorderTasks = async (items: { id: string; position: number }[]) => {
    // Optimistic update
    setTasks((prev) => {
      const updated = [...prev];
      for (const item of items) {
        const idx = updated.findIndex((t) => t.id === item.id);
        if (idx !== -1) updated[idx] = { ...updated[idx], position: item.position };
      }
      return updated.sort((a, b) => a.position - b.position);
    });
    await api.patch("/tasks/reorder", { items });
  };

  const handleAddSection = async () => {
    const trimmed = addingSectionName.trim();
    if (!trimmed) return;
    const section = await api.post<Section>(`/projects/${projectId}/sections`, {
      name: trimmed,
    });
    setSections((prev) => [...prev, section]);
    setAddingSectionName("");
    setShowAddSection(false);
  };

  const handleRenameSection = async (id: string, name: string) => {
    const updated = await api.patch<Section>(`/sections/${id}`, { name });
    setSections((prev) => prev.map((s) => (s.id === id ? updated : s)));
  };

  const handleDeleteSection = async (id: string) => {
    await api.delete(`/sections/${id}`);
    setSections((prev) => prev.filter((s) => s.id !== id));
    // Tasks in deleted section become unsectioned
    setTasks((prev) =>
      prev.map((t) => (t.section_id === id ? { ...t, section_id: null } : t))
    );
  };

  const handleSectionDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = sections.findIndex((s) => s.id === active.id);
    const newIndex = sections.findIndex((s) => s.id === over.id);
    const reordered = arrayMove(sections, oldIndex, newIndex);
    setSections(reordered);

    const items = reordered.map((s, i) => ({ id: s.id, position: i }));
    api.patch(`/projects/${projectId}/sections/reorder`, { items });
  };

  if (loading) {
    return (
      <div style={{ padding: 32, color: "var(--text-quaternary)", textAlign: "center" }}>
        読み込み中...
      </div>
    );
  }

  const unsectionedTasks = tasks.filter((t) => !t.section_id);

  return (
    <div style={{ padding: "16px 0" }}>
      {(unsectionedTasks.length > 0 || sections.length === 0) && (
        <SectionView
          section={null}
          tasks={unsectionedTasks}
          onAddTask={handleAddTask}
          onDeleteTask={handleDeleteTask}
          onClickTask={onClickTask}
          onReorderTasks={handleReorderTasks}
        />
      )}

      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleSectionDragEnd}>
        <SortableContext items={sections.map((s) => s.id)} strategy={verticalListSortingStrategy}>
          {sections.map((section) => (
            <SectionView
              key={section.id}
              sortableId={section.id}
              section={section}
              tasks={tasks.filter((t) => t.section_id === section.id)}
              onAddTask={handleAddTask}
              onDeleteTask={handleDeleteTask}
              onClickTask={onClickTask}
              onReorderTasks={handleReorderTasks}
              onRenameSection={handleRenameSection}
              onDeleteSection={handleDeleteSection}
            />
          ))}
        </SortableContext>
      </DndContext>

      {/* Add section */}
      {showAddSection ? (
        <div style={{ padding: "4px 12px", display: "flex", gap: 8 }}>
          <input
            autoFocus
            value={addingSectionName}
            onChange={(e) => setAddingSectionName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") handleAddSection();
              if (e.key === "Escape") { setShowAddSection(false); setAddingSectionName(""); }
            }}
            onBlur={() => { if (!addingSectionName.trim()) { setShowAddSection(false); } }}
            placeholder="セクション名..."
            style={{
              flex: 1,
              background: "rgba(255,255,255,0.02)",
              border: "1px solid var(--border-standard)",
              borderRadius: "var(--radius-sm)",
              color: "var(--text-primary)",
              padding: "4px 8px",
              fontSize: 13,
              outline: "none",
            }}
          />
        </div>
      ) : (
        <button
          onClick={() => setShowAddSection(true)}
          style={{
            padding: "6px 12px",
            border: "none",
            borderRadius: "var(--radius-sm)",
            background: "transparent",
            color: "var(--text-quaternary)",
            fontSize: 12,
            fontWeight: 510,
            transition: "color 0.1s",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.color = "var(--text-tertiary)")}
          onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-quaternary)")}
        >
          ＋ セクションを追加
        </button>
      )}
    </div>
  );
}

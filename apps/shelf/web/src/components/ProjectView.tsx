import { useEffect, useState, useCallback, useRef } from "react";
import {
  DndContext,
  closestCenter,
  pointerWithin,
  rectIntersection,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
  type CollisionDetection,
} from "@dnd-kit/core";
import {
  SortableContext,
  verticalListSortingStrategy,
  arrayMove,
} from "@dnd-kit/sortable";
import type { Section, Task } from "@todo-shelf/shared";
import { api } from "../lib/api";
import { SectionView } from "./SectionView";
import { useToast } from "./Toast";

interface ProjectViewProps {
  projectId: string;
  onClickTask: (task: Task) => void;
}

function parseDragId(id: string): { type: "section" | "task" | "droppable"; rawId: string } {
  const s = String(id);
  if (s.startsWith("section-")) return { type: "section", rawId: s.slice(8) };
  if (s.startsWith("task-")) return { type: "task", rawId: s.slice(5) };
  return { type: "droppable", rawId: s };
}

function sectionIdFromDroppable(droppableId: string): string | null {
  if (droppableId === "droppable-unsectioned") return null;
  if (droppableId.startsWith("droppable-section-")) return droppableId.slice(18);
  return null;
}

// Custom collision detection: prioritize task items over droppable zones
const taskAwareCollision: CollisionDetection = (args) => {
  const activeId = String(args.active.id);
  const isTaskDrag = activeId.startsWith("task-");

  if (isTaskDrag) {
    // First try pointerWithin for precise detection among tasks
    const pointerCollisions = pointerWithin(args);
    // Filter to only task and droppable collisions (not section sortables)
    const taskCollisions = pointerCollisions.filter((c) => {
      const id = String(c.id);
      return id.startsWith("task-") || id.startsWith("droppable-");
    });
    // Prefer task collisions over droppable zones
    const taskOnly = taskCollisions.filter((c) => String(c.id).startsWith("task-"));
    if (taskOnly.length > 0) return taskOnly;
    // Fall back to droppable zones (for empty sections)
    const droppableOnly = taskCollisions.filter((c) => String(c.id).startsWith("droppable-"));
    if (droppableOnly.length > 0) return droppableOnly;
    // Final fallback: rectIntersection for edge cases
    const rectCollisions = rectIntersection(args);
    return rectCollisions.filter((c) => {
      const id = String(c.id);
      return id.startsWith("task-") || id.startsWith("droppable-");
    });
  }

  // Section drag: use closestCenter among section items only
  return closestCenter(args);
};

export function ProjectView({ projectId, onClickTask }: ProjectViewProps) {
  const [sections, setSections] = useState<Section[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [addingSectionName, setAddingSectionName] = useState("");
  const [showAddSection, setShowAddSection] = useState(false);
  const dragTypeRef = useRef<"section" | "task" | null>(null);
  const { showToast } = useToast();

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
    const tempId = `temp-${Date.now()}`;
    const now = new Date().toISOString();
    const sectionTasks = tasks.filter((t) => t.section_id === sectionId);
    const optimistic: Task = {
      id: tempId,
      project_id: projectId,
      section_id: sectionId,
      title,
      due_date: null,
      position: sectionTasks.length,
      comment_count: 0,
      archived_at: null,
      created_at: now,
      updated_at: now,
    };
    setTasks((prev) => [...prev, optimistic]);
    try {
      const task = await api.post<Task>("/tasks", {
        title,
        project_id: projectId,
        section_id: sectionId,
      });
      setTasks((prev) => prev.map((t) => (t.id === tempId ? task : t)));
    } catch {
      setTasks((prev) => prev.filter((t) => t.id !== tempId));
      showToast("タスクの作成に失敗しました", () => handleAddTask(title, sectionId));
    }
  };

  const handleDeleteTask = async (id: string) => {
    const snapshot = tasks;
    setTasks((prev) => prev.filter((t) => t.id !== id));
    try {
      await api.delete(`/tasks/${id}`);
    } catch {
      setTasks(snapshot);
      showToast("タスクの削除に失敗しました", () => handleDeleteTask(id));
    }
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
    setTasks((prev) =>
      prev.map((t) => (t.section_id === id ? { ...t, section_id: null } : t))
    );
  };

  // --- Drag handlers ---

  const handleDragStart = (event: DragStartEvent) => {
    const { type } = parseDragId(String(event.active.id));
    dragTypeRef.current = type === "section" || type === "task" ? type : null;
  };

  const handleDragOver = (event: DragOverEvent) => {
    if (dragTypeRef.current !== "task") return;
    const { active, over } = event;
    if (!over) return;

    const activeInfo = parseDragId(String(active.id));
    const overInfo = parseDragId(String(over.id));
    if (activeInfo.type !== "task") return;

    const activeTask = tasks.find((t) => t.id === activeInfo.rawId);
    if (!activeTask) return;

    // Determine the target section_id
    let targetSectionId: string | null | undefined;
    if (overInfo.type === "task") {
      const overTask = tasks.find((t) => t.id === overInfo.rawId);
      if (!overTask) return;
      targetSectionId = overTask.section_id;
    } else if (overInfo.type === "droppable") {
      targetSectionId = sectionIdFromDroppable(overInfo.rawId);
    } else {
      return;
    }

    // Move task to a different section during drag (optimistic visual)
    if (targetSectionId !== undefined && activeTask.section_id !== targetSectionId) {
      setTasks((prev) =>
        prev.map((t) =>
          t.id === activeInfo.rawId ? { ...t, section_id: targetSectionId } : t
        )
      );
    }
  };

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    const currentDragType = dragTypeRef.current;
    dragTypeRef.current = null;
    if (!over || active.id === over.id) return;

    if (currentDragType === "section") {
      // Section reordering
      const activeInfo = parseDragId(String(active.id));
      const overInfo = parseDragId(String(over.id));
      if (activeInfo.type !== "section" || overInfo.type !== "section") return;

      const oldIndex = sections.findIndex((s) => s.id === activeInfo.rawId);
      const newIndex = sections.findIndex((s) => s.id === overInfo.rawId);
      if (oldIndex === -1 || newIndex === -1) return;

      const reordered = arrayMove(sections, oldIndex, newIndex);
      setSections(reordered);
      const items = reordered.map((s, i) => ({ id: s.id, position: i }));
      api.patch(`/projects/${projectId}/sections/reorder`, { items });
      return;
    }

    if (currentDragType === "task") {
      const activeInfo = parseDragId(String(active.id));
      const overInfo = parseDragId(String(over.id));
      if (activeInfo.type !== "task") return;

      const activeTask = tasks.find((t) => t.id === activeInfo.rawId);
      if (!activeTask) return;

      // Target section was already updated in onDragOver
      const targetSectionId = activeTask.section_id;

      // Get all tasks in the target section (including active), sorted
      const allSectionTasks = tasks
        .filter((t) => t.section_id === targetSectionId)
        .sort((a, b) => a.position - b.position);

      let reordered: Task[];

      if (overInfo.type === "task") {
        // Use arrayMove for correct handling of drag direction
        const oldIndex = allSectionTasks.findIndex((t) => t.id === activeInfo.rawId);
        const newIndex = allSectionTasks.findIndex((t) => t.id === overInfo.rawId);
        if (oldIndex === -1 || newIndex === -1) return;
        reordered = arrayMove(allSectionTasks, oldIndex, newIndex);
      } else {
        // Dropped on empty section droppable — move to end
        const withoutActive = allSectionTasks.filter((t) => t.id !== activeInfo.rawId);
        reordered = [...withoutActive, activeTask];
      }

      // Build reorder items with section_id
      const reorderItems = reordered.map((t, i) => ({
        id: t.id,
        position: i,
        section_id: targetSectionId,
      }));

      // Optimistic update
      setTasks((prev) => {
        const others = prev.filter(
          (t) => t.section_id !== targetSectionId && t.id !== activeInfo.rawId
        );
        const updated = reordered.map((t, i) => ({
          ...t,
          position: i,
          section_id: targetSectionId,
        }));
        return [...others, ...updated];
      });

      api.patch("/tasks/reorder", { items: reorderItems });
    }
  };

  if (loading) {
    return (
      <div style={{ padding: 32, color: "var(--text-quaternary)", textAlign: "center" }}>
        読み込み中...
      </div>
    );
  }

  const unsectionedTasks = tasks
    .filter((t) => !t.section_id)
    .sort((a, b) => a.position - b.position);
  const sectionIds = sections.map((s) => `section-${s.id}`);

  return (
    <div style={{ padding: "16px 0" }}>
      <DndContext
        sensors={sensors}
        collisionDetection={taskAwareCollision}
        onDragStart={handleDragStart}
        onDragOver={handleDragOver}
        onDragEnd={handleDragEnd}
      >
        <SectionView
          section={null}
          tasks={unsectionedTasks}
          onAddTask={handleAddTask}
          onDeleteTask={handleDeleteTask}
          onClickTask={onClickTask}
        />

        <SortableContext items={sectionIds} strategy={verticalListSortingStrategy}>
          {sections.map((section) => (
            <SectionView
              key={section.id}
              sortableId={`section-${section.id}`}
              section={section}
              tasks={tasks
                .filter((t) => t.section_id === section.id)
                .sort((a, b) => a.position - b.position)}
              onAddTask={handleAddTask}
              onDeleteTask={handleDeleteTask}
              onClickTask={onClickTask}
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

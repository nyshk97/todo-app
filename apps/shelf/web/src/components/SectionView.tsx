import { useState } from "react";
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
  useSortable,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { Section, Task } from "@todo-shelf/shared";
import { TaskItem } from "./TaskItem";
import { AddTask } from "./AddTask";

interface SectionViewProps {
  section: Section | null;
  tasks: Task[];
  onAddTask: (title: string, sectionId: string | null) => void;
  onDeleteTask: (id: string) => void;
  onClickTask: (task: Task) => void;
  onReorderTasks: (items: { id: string; position: number }[]) => void;
  onRenameSection?: (id: string, name: string) => void;
  onDeleteSection?: (id: string) => void;
  sortableId?: string;
}

function SectionHeader({
  section,
  onRename,
  onDelete,
  dragHandleProps,
}: {
  section: Section;
  onRename?: (id: string, name: string) => void;
  onDelete?: (id: string) => void;
  dragHandleProps?: Record<string, unknown>;
}) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(section.name);

  const handleSubmit = () => {
    const trimmed = name.trim();
    if (trimmed && trimmed !== section.name && onRename) {
      onRename(section.id, trimmed);
    }
    setEditing(false);
  };

  return (
    <div style={{
      display: "flex",
      alignItems: "center",
      gap: 6,
      padding: "4px 12px",
    }}>
      {dragHandleProps && (
        <span
          {...dragHandleProps}
          style={{
            cursor: "grab",
            color: "var(--text-quaternary)",
            fontSize: 10,
            userSelect: "none",
            touchAction: "none",
          }}
        >
          ⠿
        </span>
      )}
      {editing ? (
        <input
          autoFocus
          value={name}
          onChange={(e) => setName(e.target.value)}
          onBlur={handleSubmit}
          onKeyDown={(e) => {
            if (e.key === "Enter") handleSubmit();
            if (e.key === "Escape") { setName(section.name); setEditing(false); }
          }}
          style={{
            background: "rgba(255,255,255,0.02)",
            border: "1px solid var(--border-standard)",
            borderRadius: "var(--radius-sm)",
            color: "var(--text-tertiary)",
            fontSize: 13,
            fontWeight: 510,
            padding: "2px 6px",
            outline: "none",
            textTransform: "uppercase",
          }}
        />
      ) : (
        <h3
          onDoubleClick={() => setEditing(true)}
          style={{
            fontSize: 13,
            fontWeight: 510,
            color: "var(--text-tertiary)",
            letterSpacing: "-0.13px",
            textTransform: "uppercase",
            cursor: "default",
          }}
        >
          {section.name}
        </h3>
      )}
      {onDelete && (
        <button
          onClick={() => onDelete(section.id)}
          style={{
            marginLeft: "auto",
            background: "transparent",
            border: "none",
            color: "var(--text-quaternary)",
            fontSize: 12,
            opacity: 0,
            transition: "opacity 0.1s",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.opacity = "1")}
          onMouseLeave={(e) => (e.currentTarget.style.opacity = "0")}
        >
          ×
        </button>
      )}
    </div>
  );
}

export function SectionView({
  section,
  tasks,
  onAddTask,
  onDeleteTask,
  onClickTask,
  onReorderTasks,
  onRenameSection,
  onDeleteSection,
  sortableId,
}: SectionViewProps) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
  );

  const sortable = useSortable({ id: sortableId ?? "unsectioned", disabled: !sortableId });

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = tasks.findIndex((t) => t.id === active.id);
    const newIndex = tasks.findIndex((t) => t.id === over.id);
    const reordered = arrayMove(tasks, oldIndex, newIndex);
    onReorderTasks(reordered.map((t, i) => ({ id: t.id, position: i })));
  };

  const style = sortableId
    ? {
        transform: CSS.Transform.toString(sortable.transform),
        transition: sortable.transition,
        opacity: sortable.isDragging ? 0.5 : 1,
      }
    : {};

  return (
    <div ref={sortableId ? sortable.setNodeRef : undefined} style={{ ...style, marginBottom: 24 }}>
      {section && (
        <SectionHeader
          section={section}
          onRename={onRenameSection}
          onDelete={onDeleteSection}
          dragHandleProps={sortableId ? { ...sortable.attributes, ...sortable.listeners } : undefined}
        />
      )}
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={tasks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
          {tasks.map((task) => (
            <TaskItem
              key={task.id}
              task={task}
              onDelete={onDeleteTask}
              onClick={onClickTask}
            />
          ))}
        </SortableContext>
      </DndContext>
      <AddTask onAdd={(title) => onAddTask(title, section?.id ?? null)} />
    </div>
  );
}

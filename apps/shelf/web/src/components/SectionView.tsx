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
  const [showMenu, setShowMenu] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

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
      padding: "8px 12px 6px",
      marginTop: 8,
      borderBottom: "1px solid var(--border-subtle)",
      position: "relative",
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
            color: "var(--text-primary)",
            fontSize: 13,
            fontWeight: 600,
            padding: "2px 6px",
            outline: "none",
          }}
        />
      ) : (
        <h3
          onDoubleClick={() => setEditing(true)}
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: "var(--text-primary)",
            letterSpacing: "-0.13px",
            cursor: "default",
            margin: 0,
          }}
        >
          {section.name}
        </h3>
      )}
      {(onDelete || onRename) && (
        <button
          onClick={() => { setShowMenu(!showMenu); setConfirmDelete(false); }}
          style={{
            marginLeft: "auto",
            background: "transparent",
            border: "none",
            color: "var(--text-quaternary)",
            fontSize: 14,
            padding: "2px 6px",
            cursor: "pointer",
            lineHeight: 1,
          }}
        >
          ⋯
        </button>
      )}

      {showMenu && (
        <>
          <div
            style={{ position: "fixed", inset: 0, zIndex: 49 }}
            onClick={() => { setShowMenu(false); setConfirmDelete(false); }}
          />
          <div style={{
            position: "absolute",
            top: "100%",
            right: 0,
            marginTop: 4,
            background: "var(--bg-surface)",
            border: "1px solid var(--border-standard)",
            borderRadius: "var(--radius-md)",
            padding: 4,
            minWidth: 140,
            zIndex: 50,
          }}>
            {onRename && (
              <button
                onClick={() => { setEditing(true); setShowMenu(false); }}
                style={{
                  display: "block",
                  width: "100%",
                  textAlign: "left",
                  padding: "6px 10px",
                  border: "none",
                  borderRadius: "var(--radius-sm)",
                  background: "transparent",
                  color: "var(--text-secondary)",
                  fontSize: 12,
                  cursor: "pointer",
                }}
                onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.05)")}
                onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
              >
                名前を変更
              </button>
            )}
            {onDelete && !confirmDelete && (
              <button
                onClick={() => setConfirmDelete(true)}
                style={{
                  display: "block",
                  width: "100%",
                  textAlign: "left",
                  padding: "6px 10px",
                  border: "none",
                  borderRadius: "var(--radius-sm)",
                  background: "transparent",
                  color: "var(--color-red)",
                  fontSize: 12,
                  cursor: "pointer",
                }}
                onMouseEnter={(e) => (e.currentTarget.style.background = "rgba(255,255,255,0.05)")}
                onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
              >
                削除
              </button>
            )}
            {onDelete && confirmDelete && (
              <div style={{ padding: "4px 10px" }}>
                <p style={{ fontSize: 11, color: "var(--text-tertiary)", margin: "0 0 6px" }}>
                  タスクはセクション未所属になります
                </p>
                <div style={{ display: "flex", gap: 4 }}>
                  <button
                    onClick={() => { onDelete(section.id); setShowMenu(false); }}
                    style={{
                      padding: "4px 10px",
                      borderRadius: "var(--radius-sm)",
                      border: "none",
                      background: "var(--color-red)",
                      color: "#fff",
                      fontSize: 11,
                      fontWeight: 510,
                      cursor: "pointer",
                    }}
                  >
                    削除する
                  </button>
                  <button
                    onClick={() => setConfirmDelete(false)}
                    style={{
                      padding: "4px 10px",
                      borderRadius: "var(--radius-sm)",
                      border: "1px solid var(--border-standard)",
                      background: "transparent",
                      color: "var(--text-tertiary)",
                      fontSize: 11,
                      cursor: "pointer",
                    }}
                  >
                    戻す
                  </button>
                </div>
              </div>
            )}
          </div>
        </>
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

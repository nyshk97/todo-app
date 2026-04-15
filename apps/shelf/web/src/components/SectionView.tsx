import type { Section, Task } from "@todo-shelf/shared";
import { TaskItem } from "./TaskItem";
import { AddTask } from "./AddTask";

interface SectionViewProps {
  section: Section | null; // null = unsectioned tasks
  tasks: Task[];
  onAddTask: (title: string, sectionId: string | null) => void;
  onDeleteTask: (id: string) => void;
  onClickTask: (task: Task) => void;
}

export function SectionView({ section, tasks, onAddTask, onDeleteTask, onClickTask }: SectionViewProps) {
  return (
    <div style={{ marginBottom: 24 }}>
      {section && (
        <h3 style={{
          padding: "4px 12px",
          fontSize: 13,
          fontWeight: 510,
          color: "var(--text-tertiary)",
          letterSpacing: "-0.13px",
          textTransform: "uppercase",
        }}>
          {section.name}
        </h3>
      )}
      <div>
        {tasks.map((task) => (
          <TaskItem
            key={task.id}
            task={task}
            onDelete={onDeleteTask}
            onClick={onClickTask}
          />
        ))}
        <AddTask onAdd={(title) => onAddTask(title, section?.id ?? null)} />
      </div>
    </div>
  );
}

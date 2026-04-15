import { useEffect, useState, useCallback } from "react";
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

  if (loading) {
    return (
      <div style={{ padding: 32, color: "var(--text-quaternary)", textAlign: "center" }}>
        読み込み中...
      </div>
    );
  }

  // unsectioned tasks
  const unsectionedTasks = tasks.filter((t) => !t.section_id);

  return (
    <div style={{ padding: "16px 0" }}>
      {unsectionedTasks.length > 0 || sections.length === 0 ? (
        <SectionView
          section={null}
          tasks={unsectionedTasks}
          onAddTask={handleAddTask}
          onDeleteTask={handleDeleteTask}
          onClickTask={onClickTask}
        />
      ) : null}

      {sections.map((section) => (
        <SectionView
          key={section.id}
          section={section}
          tasks={tasks.filter((t) => t.section_id === section.id)}
          onAddTask={handleAddTask}
          onDeleteTask={handleDeleteTask}
          onClickTask={onClickTask}
        />
      ))}
    </div>
  );
}

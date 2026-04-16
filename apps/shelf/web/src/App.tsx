import { useEffect, useState } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  useParams,
  useNavigate,
  useLocation,
} from "react-router-dom";
import type { Project, Task, Section, UpcomingTask } from "@todo-shelf/shared";
import { api } from "./lib/api";
import { TabNav } from "./components/TabNav";
import { ProjectView } from "./components/ProjectView";
import { TaskDetail } from "./components/TaskDetail";
import { ArchiveView } from "./components/ArchiveView";
import { ToastProvider, useToast } from "./components/Toast";

function Shell() {
  const { projectId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const [projects, setProjects] = useState<Project[]>([]);
  const [allSections, setAllSections] = useState<Section[]>([]);
  const [upcomingCount, setUpcomingCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const { showToast } = useToast();

  const isArchive = location.pathname === "/archive";

  useEffect(() => {
    (async () => {
      const [ps, upcoming] = await Promise.all([
        api.get<Project[]>("/projects"),
        api.get<UpcomingTask[]>("/tasks/upcoming?days=3"),
      ]);
      setProjects(ps);
      setUpcomingCount(upcoming.length);

      // Fetch all sections for move UI
      const sectionResults = await Promise.all(
        ps.map((p) => api.get<Section[]>(`/projects/${p.id}/sections`))
      );
      setAllSections(sectionResults.flat());

      setLoading(false);

      if (!isArchive && ps.length > 0 && (!projectId || !ps.find((p) => p.id === projectId))) {
        navigate(`/projects/${ps[0].id}`, { replace: true });
      }
    })();
  }, []);

  const handleSelect = (id: string) => {
    if (id === "__archive__") {
      navigate("/archive");
    } else {
      navigate(`/projects/${id}`);
    }
  };

  const handleTaskUpdate = (updated: Task) => {
    setSelectedTask(updated);
    setRefreshKey((k) => k + 1);
  };

  const handleTaskDelete = async (id: string) => {
    setSelectedTask(null);
    setRefreshKey((k) => k + 1);
    try {
      await api.delete(`/tasks/${id}`);
    } catch {
      setRefreshKey((k) => k + 1);
      showToast("タスクの削除に失敗しました", () => handleTaskDelete(id));
    }
  };

  const handleMoveToToday = async (id: string) => {
    const task = selectedTask;
    if (!task) return;

    // 1. todo-appにタスク作成（クライアントから直接）
    const todoAppUrl = import.meta.env.VITE_TODO_APP_API_URL ?? "http://localhost:8788";
    const todoAppSecret = import.meta.env.VITE_API_SECRET ?? "";
    const today = new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const res = await fetch(`${todoAppUrl}/todos`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${todoAppSecret}`,
      },
      body: JSON.stringify({
        title: task.section_id
          ? `[${allSections.find((s) => s.id === task.section_id)?.name}] ${task.title}`
          : task.title,
        date: today,
      }),
    });
    if (!res.ok) {
      throw new Error("Failed to create todo in todo-app");
    }

    // 2. Shelf側でアーカイブ
    await api.post(`/tasks/${id}/move-to-today`, {});
    setSelectedTask(null);
    setRefreshKey((k) => k + 1);
  };

  if (loading) {
    return (
      <div style={{
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: "var(--text-quaternary)",
      }}>
        読み込み中...
      </div>
    );
  }

  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
      <TabNav
        projects={projects}
        activeId={isArchive ? "__archive__" : (projectId ?? null)}
        upcomingCount={upcomingCount}
        onSelect={handleSelect}
        onProjectsChange={setProjects}
      />
      <main style={{
        flex: 1,
        overflow: "auto",
        maxWidth: 720,
        width: "100%",
        margin: "0 auto",
        padding: "0 16px",
      }}>
        {isArchive ? (
          <ArchiveView
            key={refreshKey}
            projects={projects}
            sections={allSections}
          />
        ) : projectId ? (
          <ProjectView
            key={`${projectId}-${refreshKey}`}
            projectId={projectId}
            onClickTask={setSelectedTask}
          />
        ) : (
          <div style={{
            padding: 64,
            textAlign: "center",
            color: "var(--text-quaternary)",
          }}>
            プロジェクトがありません
          </div>
        )}
      </main>

      {selectedTask && !isArchive && (
        <TaskDetail
          task={selectedTask}
          projects={projects}
          sections={allSections}
          onUpdate={handleTaskUpdate}
          onDelete={handleTaskDelete}
          onMoveToToday={handleMoveToToday}
          onClose={() => setSelectedTask(null)}
        />
      )}
    </div>
  );
}

export default function App() {
  return (
    <ToastProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/projects/:projectId" element={<Shell />} />
          <Route path="/archive" element={<Shell />} />
          <Route path="*" element={<Shell />} />
        </Routes>
      </BrowserRouter>
    </ToastProvider>
  );
}

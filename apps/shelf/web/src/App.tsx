import { useEffect, useState } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  useParams,
  useNavigate,
  useLocation,
} from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { Project, Task, Section, UpcomingTask } from "@todo-shelf/shared";
import { api, recordSlowRequest } from "./lib/api";
import { Header } from "./components/Header";
import { Fab } from "./components/Fab";
import { ProjectView } from "./components/ProjectView";
import { TaskDetail } from "./components/TaskDetail";
import { ArchiveView } from "./components/ArchiveView";
import { ToastProvider, useToast } from "./components/Toast";

/** Find the "main" project (Shelf or Deck, or first project) */
function findMainProject(projects: Project[]): Project | undefined {
  return (
    projects.find((p) => p.name === "Shelf") ??
    projects.find((p) => p.name === "Deck") ??
    projects[0]
  );
}

function Shell() {
  const { projectId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const queryClient = useQueryClient();
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const { showToast } = useToast();

  const isArchive = location.pathname === "/archive";

  // フォーカス時の再取得は TanStack Query の refetchOnWindowFocus（デフォルト有効）に任せる
  const { data: projects = [], isPending: projectsPending } = useQuery({
    queryKey: ["projects"],
    queryFn: () => api.get<Project[]>("/projects"),
  });
  const { data: allSections = [] } = useQuery({
    queryKey: ["sections"],
    queryFn: () => api.get<Section[]>("/sections"),
  });
  const { data: upcoming = [] } = useQuery({
    queryKey: ["upcoming"],
    queryFn: () => api.get<UpcomingTask[]>("/tasks/upcoming?days=3"),
  });

  const backlogProject = projects.find((p) => p.name === "Backlog");
  const backlogUpcomingCount = backlogProject
    ? upcoming.filter((t) => t.project_id === backlogProject.id).length
    : 0;

  // URL のプロジェクトが不在ならメインプロジェクトへリダイレクト
  useEffect(() => {
    if (isArchive || projects.length === 0) return;
    if (!projectId || !projects.find((p) => p.id === projectId)) {
      const main = findMainProject(projects);
      if (main) navigate(`/projects/${main.id}`, { replace: true });
    }
  }, [projects, projectId, isArchive, navigate]);

  const invalidateTaskQueries = () => {
    queryClient.invalidateQueries({ queryKey: ["tasks"] });
    queryClient.invalidateQueries({ queryKey: ["upcoming"] });
  };

  const handleNavigate = (path: string) => {
    navigate(path);
  };

  const handleProjectsChange = (ps: Project[]) => {
    queryClient.setQueryData(["projects"], ps);
    queryClient.invalidateQueries({ queryKey: ["projects"] });
    queryClient.invalidateQueries({ queryKey: ["sections"] });
  };

  const handleTaskUpdate = (updated: Task) => {
    setSelectedTask(updated);
    invalidateTaskQueries();
  };

  const handleTaskDelete = async (id: string) => {
    setSelectedTask(null);
    try {
      await api.delete(`/tasks/${id}`);
      invalidateTaskQueries();
    } catch {
      showToast("タスクの削除に失敗しました", () => handleTaskDelete(id));
    }
  };

  const handleMoveToToday = async (id: string) => {
    const task = selectedTask;
    if (!task) return;

    const todoAppUrl = import.meta.env.VITE_TODO_APP_API_URL ?? "http://localhost:8788";
    const todoAppSecret = import.meta.env.VITE_API_SECRET ?? "";
    const today = new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const start = performance.now();
    let res: Response;
    try {
      res = await fetch(`${todoAppUrl}/todos`, {
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
    } catch (e) {
      recordSlowRequest({
        at: new Date().toISOString(),
        method: "POST",
        path: "todo-app:/todos",
        ms: Math.round(performance.now() - start),
        status: "network-error",
      });
      throw e;
    }
    const ms = Math.round(performance.now() - start);
    if (ms > 1000) {
      recordSlowRequest({
        at: new Date().toISOString(),
        method: "POST",
        path: "todo-app:/todos",
        ms,
        status: res.status,
      });
    }
    if (!res.ok) {
      throw new Error("Failed to create todo in todo-app");
    }

    await api.post(`/tasks/${id}/move-to-today`, {});
    setSelectedTask(null);
    invalidateTaskQueries();
    queryClient.invalidateQueries({ queryKey: ["archived"] });
  };

  // キャッシュがあれば isPending は false になり、この画面は初回アクセス時のみ表示される
  if (projectsPending) {
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

  // Determine current view context
  const mainProject = findMainProject(projects);
  const currentProject = projects.find((p) => p.id === projectId);
  const isMainProject = currentProject?.id === mainProject?.id;
  const showFab = isMainProject && !isArchive;

  // Header props
  let headerTitle = "Shelf";
  let backTo: string | undefined;
  let backLabel: string | undefined;

  if (isArchive) {
    headerTitle = "Archive";
    backTo = mainProject ? `/projects/${mainProject.id}` : undefined;
    backLabel = mainProject?.name ?? "Shelf";
  } else if (currentProject && !isMainProject) {
    headerTitle = currentProject.name;
    backTo = mainProject ? `/projects/${mainProject.id}` : undefined;
    backLabel = mainProject?.name ?? "Shelf";
  } else if (currentProject) {
    headerTitle = currentProject.name;
  }

  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
      <Header
        title={headerTitle}
        backTo={backTo}
        backLabel={backLabel}
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
            projects={projects}
            sections={allSections}
          />
        ) : projectId ? (
          <ProjectView
            key={projectId}
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

      {showFab && (
        <Fab
          projects={projects}
          backlogUpcomingCount={backlogUpcomingCount}
          onNavigate={handleNavigate}
          onProjectsChange={handleProjectsChange}
        />
      )}

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

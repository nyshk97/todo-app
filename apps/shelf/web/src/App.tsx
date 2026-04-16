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
  const [projects, setProjects] = useState<Project[]>([]);
  const [allSections, setAllSections] = useState<Section[]>([]);
  const [vaultUpcomingCount, setVaultUpcomingCount] = useState(0);
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

      // Count upcoming tasks in Vault project only
      const vaultProject = ps.find((p) => p.name === "Vault");
      if (vaultProject) {
        setVaultUpcomingCount(
          upcoming.filter((t) => t.project_id === vaultProject.id).length
        );
      }

      // Fetch all sections for move UI
      const sectionResults = await Promise.all(
        ps.map((p) => api.get<Section[]>(`/projects/${p.id}/sections`))
      );
      setAllSections(sectionResults.flat());

      setLoading(false);

      // Default: navigate to main project
      if (!isArchive && ps.length > 0 && (!projectId || !ps.find((p) => p.id === projectId))) {
        const main = findMainProject(ps);
        if (main) navigate(`/projects/${main.id}`, { replace: true });
      }
    })();
  }, []);

  const handleNavigate = (path: string) => {
    navigate(path);
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

      {showFab && (
        <Fab
          projects={projects}
          vaultUpcomingCount={vaultUpcomingCount}
          onNavigate={handleNavigate}
          onProjectsChange={setProjects}
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

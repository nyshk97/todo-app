import { useEffect, useState } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  useParams,
  useNavigate,
} from "react-router-dom";
import type { Project, Task, Section, UpcomingTask } from "@todo-shelf/shared";
import { api } from "./lib/api";
import { TabNav } from "./components/TabNav";
import { ProjectView } from "./components/ProjectView";
import { TaskDetail } from "./components/TaskDetail";

function Shell() {
  const { projectId } = useParams();
  const navigate = useNavigate();
  const [projects, setProjects] = useState<Project[]>([]);
  const [allSections, setAllSections] = useState<Section[]>([]);
  const [upcomingCount, setUpcomingCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

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

      if (ps.length > 0 && (!projectId || !ps.find((p) => p.id === projectId))) {
        navigate(`/projects/${ps[0].id}`, { replace: true });
      }
    })();
  }, []);

  const handleSelect = (id: string) => {
    navigate(`/projects/${id}`);
  };

  const handleTaskUpdate = (updated: Task) => {
    setSelectedTask(updated);
    setRefreshKey((k) => k + 1);
  };

  const handleTaskDelete = async (id: string) => {
    await api.delete(`/tasks/${id}`);
    setSelectedTask(null);
    setRefreshKey((k) => k + 1);
  };

  const handleMoveToToday = async (id: string) => {
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
        activeId={projectId ?? null}
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
        {projectId ? (
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

      {selectedTask && (
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
    <BrowserRouter>
      <Routes>
        <Route path="/projects/:projectId" element={<Shell />} />
        <Route path="*" element={<Shell />} />
      </Routes>
    </BrowserRouter>
  );
}

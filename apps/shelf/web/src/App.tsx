import { useEffect, useState } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  useParams,
  useNavigate,
} from "react-router-dom";
import type { Project, Task, UpcomingTask } from "@todo-shelf/shared";
import { api } from "./lib/api";
import { TabNav } from "./components/TabNav";
import { ProjectView } from "./components/ProjectView";

function Shell() {
  const { projectId } = useParams();
  const navigate = useNavigate();
  const [projects, setProjects] = useState<Project[]>([]);
  const [upcomingCount, setUpcomingCount] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const [ps, upcoming] = await Promise.all([
        api.get<Project[]>("/projects"),
        api.get<UpcomingTask[]>("/tasks/upcoming?days=3"),
      ]);
      setProjects(ps);
      setUpcomingCount(upcoming.length);
      setLoading(false);

      // projectId が未指定 or 存在しないプロジェクトなら最初のプロジェクトへ
      if (ps.length > 0 && (!projectId || !ps.find((p) => p.id === projectId))) {
        navigate(`/projects/${ps[0].id}`, { replace: true });
      }
    })();
  }, []);

  const handleSelect = (id: string) => {
    navigate(`/projects/${id}`);
  };

  const handleClickTask = (task: Task) => {
    // Phase 5 で詳細パネルを実装
    console.log("task clicked:", task.id);
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
            key={projectId}
            projectId={projectId}
            onClickTask={handleClickTask}
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

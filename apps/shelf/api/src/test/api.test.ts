import {
  describe,
  it,
  expect,
  beforeAll,
} from "vitest";
import { env } from "cloudflare:test";
import app from "../index";
import { req, json } from "./helpers";

// Apply migration before tests
beforeAll(async () => {
  const migration = `
    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS sections (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      section_id TEXT REFERENCES sections(id) ON DELETE SET NULL,
      title TEXT NOT NULL,
      due_date TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS comments (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `;
  for (const stmt of migration.split(";").filter((s) => s.trim())) {
    await env.DB.prepare(stmt).run();
  }
});

describe("Auth", () => {
  it("rejects requests without auth", async () => {
    const res = await app.fetch(
      new Request("http://localhost/projects"),
      env
    );
    expect(res.status).toBe(401);
  });

  it("allows health check without auth", async () => {
    const res = await app.fetch(
      new Request("http://localhost/"),
      env
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok" });
  });
});

describe("Projects", () => {
  let projectId: string;

  it("creates a project", async () => {
    const res = await req("/projects", {
      method: "POST",
      body: { name: "TODO" },
    });
    expect(res.status).toBe(201);
    const data = await json<{ id: string; name: string; position: number }>(res);
    expect(data.name).toBe("TODO");
    expect(data.position).toBe(0);
    projectId = data.id;
  });

  it("lists projects", async () => {
    const res = await req("/projects");
    expect(res.status).toBe(200);
    const data = await json<unknown[]>(res);
    expect(data.length).toBeGreaterThanOrEqual(1);
  });

  it("updates a project", async () => {
    const res = await req(`/projects/${projectId}`, {
      method: "PATCH",
      body: { name: "TODO Updated" },
    });
    expect(res.status).toBe(200);
    const data = await json<{ name: string }>(res);
    expect(data.name).toBe("TODO Updated");
  });

  it("returns 404 for unknown project", async () => {
    const res = await req("/projects/nonexistent", { method: "PATCH", body: { name: "x" } });
    expect(res.status).toBe(404);
  });
});

describe("Sections", () => {
  let projectId: string;
  let sectionId: string;

  beforeAll(async () => {
    const res = await req("/projects", {
      method: "POST",
      body: { name: "Section Test Project" },
    });
    const data = await json<{ id: string }>(res);
    projectId = data.id;
  });

  it("creates a section", async () => {
    const res = await req(`/projects/${projectId}/sections`, {
      method: "POST",
      body: { name: "仕事" },
    });
    expect(res.status).toBe(201);
    const data = await json<{ id: string; name: string; position: number }>(res);
    expect(data.name).toBe("仕事");
    expect(data.position).toBe(0);
    sectionId = data.id;
  });

  it("lists sections", async () => {
    const res = await req(`/projects/${projectId}/sections`);
    const data = await json<unknown[]>(res);
    expect(data.length).toBe(1);
  });

  it("updates a section", async () => {
    const res = await req(`/sections/${sectionId}`, {
      method: "PATCH",
      body: { name: "プライベート" },
    });
    expect(res.status).toBe(200);
    const data = await json<{ name: string }>(res);
    expect(data.name).toBe("プライベート");
  });

  it("reorders sections", async () => {
    const res2 = await req(`/projects/${projectId}/sections`, {
      method: "POST",
      body: { name: "趣味" },
    });
    const s2 = await json<{ id: string }>(res2);

    const res = await req(`/projects/${projectId}/sections/reorder`, {
      method: "PATCH",
      body: {
        items: [
          { id: sectionId, position: 1 },
          { id: s2.id, position: 0 },
        ],
      },
    });
    expect(res.status).toBe(200);

    const listRes = await req(`/projects/${projectId}/sections`);
    const list = await json<{ id: string; position: number }[]>(listRes);
    expect(list[0].id).toBe(s2.id);
    expect(list[1].id).toBe(sectionId);
  });

  it("deletes a section", async () => {
    const res = await req(`/sections/${sectionId}`, { method: "DELETE" });
    expect(res.status).toBe(204);
  });
});

describe("Tasks", () => {
  let projectId: string;
  let sectionId: string;
  let taskId: string;

  beforeAll(async () => {
    const pRes = await req("/projects", {
      method: "POST",
      body: { name: "Task Test Project" },
    });
    projectId = (await json<{ id: string }>(pRes)).id;

    const sRes = await req(`/projects/${projectId}/sections`, {
      method: "POST",
      body: { name: "Work" },
    });
    sectionId = (await json<{ id: string }>(sRes)).id;
  });

  it("creates a task with section", async () => {
    const res = await req("/tasks", {
      method: "POST",
      body: { title: "タスク1", project_id: projectId, section_id: sectionId },
    });
    expect(res.status).toBe(201);
    const data = await json<{ id: string; section_id: string; title: string }>(res);
    expect(data.title).toBe("タスク1");
    expect(data.section_id).toBe(sectionId);
    taskId = data.id;
  });

  it("creates a task without section", async () => {
    const res = await req("/tasks", {
      method: "POST",
      body: { title: "セクションなし", project_id: projectId },
    });
    expect(res.status).toBe(201);
    const data = await json<{ section_id: string | null }>(res);
    expect(data.section_id).toBeNull();
  });

  it("lists tasks for project", async () => {
    const res = await req(`/projects/${projectId}/tasks`);
    const data = await json<unknown[]>(res);
    expect(data.length).toBe(2);
  });

  it("updates task with due_date", async () => {
    const res = await req(`/tasks/${taskId}`, {
      method: "PATCH",
      body: { due_date: "2026-04-20" },
    });
    expect(res.status).toBe(200);
    const data = await json<{ due_date: string }>(res);
    expect(data.due_date).toBe("2026-04-20");
  });

  it("clears task due_date with null", async () => {
    const res = await req(`/tasks/${taskId}`, {
      method: "PATCH",
      body: { due_date: null },
    });
    expect(res.status).toBe(200);
    const data = await json<{ due_date: string | null }>(res);
    expect(data.due_date).toBeNull();
  });

  it("moves task to different section (null)", async () => {
    const res = await req(`/tasks/${taskId}`, {
      method: "PATCH",
      body: { section_id: null },
    });
    expect(res.status).toBe(200);
    const data = await json<{ section_id: string | null }>(res);
    expect(data.section_id).toBeNull();
  });

  it("reorders tasks", async () => {
    const listRes = await req(`/projects/${projectId}/tasks`);
    const tasks = await json<{ id: string }[]>(listRes);

    const res = await req("/tasks/reorder", {
      method: "PATCH",
      body: {
        items: tasks.map((t, i) => ({ id: t.id, position: tasks.length - 1 - i })),
      },
    });
    expect(res.status).toBe(200);
  });

  it("returns upcoming tasks", async () => {
    await req(`/tasks/${taskId}`, {
      method: "PATCH",
      body: { due_date: "2026-04-16" },
    });

    const res = await req("/tasks/upcoming?days=3");
    expect(res.status).toBe(200);
    const data = await json<{ id: string; project_name: string }[]>(res);
    expect(data.length).toBeGreaterThanOrEqual(1);
    expect(data[0].project_name).toBe("Task Test Project");
  });

  it("deletes a task", async () => {
    const res = await req(`/tasks/${taskId}`, { method: "DELETE" });
    expect(res.status).toBe(204);
  });
});

describe("Comments", () => {
  let taskId: string;
  let commentId: string;

  beforeAll(async () => {
    const pRes = await req("/projects", {
      method: "POST",
      body: { name: "Comment Test Project" },
    });
    const projectId = (await json<{ id: string }>(pRes)).id;

    const tRes = await req("/tasks", {
      method: "POST",
      body: { title: "Comment Task", project_id: projectId },
    });
    taskId = (await json<{ id: string }>(tRes)).id;
  });

  it("creates a comment", async () => {
    const res = await req(`/tasks/${taskId}/comments`, {
      method: "POST",
      body: { content: "テストコメント https://example.com" },
    });
    expect(res.status).toBe(201);
    const data = await json<{ id: string; content: string }>(res);
    expect(data.content).toBe("テストコメント https://example.com");
    commentId = data.id;
  });

  it("lists comments", async () => {
    const res = await req(`/tasks/${taskId}/comments`);
    const data = await json<unknown[]>(res);
    expect(data.length).toBe(1);
  });

  it("updates a comment", async () => {
    const res = await req(`/comments/${commentId}`, {
      method: "PATCH",
      body: { content: "更新済み" },
    });
    expect(res.status).toBe(200);
    const data = await json<{ content: string }>(res);
    expect(data.content).toBe("更新済み");
  });

  it("deletes a comment", async () => {
    const res = await req(`/comments/${commentId}`, { method: "DELETE" });
    expect(res.status).toBe(204);
  });
});

/**
 * Todoist → todo-shelf 移行スクリプト
 *
 * Usage:
 *   npx tsx scripts/migrate-from-todoist.ts
 *
 * Environment variables:
 *   TODOIST_TOKEN    - Todoist API token
 *   SHELF_API_URL    - todo-shelf API URL (default: http://localhost:8787)
 *   SHELF_API_SECRET - todo-shelf API secret
 *   DRY_RUN          - "true" でドライラン（実際には書き込まない）
 */

const TODOIST_TOKEN = process.env.TODOIST_TOKEN!;
const SHELF_API_URL = process.env.SHELF_API_URL ?? "http://localhost:8787";
const SHELF_API_SECRET = process.env.SHELF_API_SECRET!;
const DRY_RUN = process.env.DRY_RUN === "true";

const TODOIST_BASE = "https://api.todoist.com/api/v1";

// 移行対象プロジェクト名（Inbox は除外）
const TARGET_PROJECTS = ["TODO", "アイデア", "いつか"];

// --- Todoist API ---

async function todoistGet<T>(path: string): Promise<T> {
  const res = await fetch(`${TODOIST_BASE}${path}`, {
    headers: { Authorization: `Bearer ${TODOIST_TOKEN}` },
  });
  if (!res.ok) throw new Error(`Todoist GET ${path}: ${res.status}`);
  return res.json() as Promise<T>;
}

interface TodoistProject {
  id: string;
  name: string;
  child_order: number;
}

interface TodoistSection {
  id: string;
  project_id: string;
  name: string;
  section_order: number;
}

interface TodoistTask {
  id: string;
  project_id: string;
  section_id: string | null;
  content: string;
  due: { date: string } | null;
  child_order: number;
}

interface TodoistComment {
  id: string;
  task_id: string;
  content: string;
  posted_at: string;
}

// --- Shelf API ---

async function shelfPost<T>(path: string, body: unknown): Promise<T> {
  if (DRY_RUN) {
    console.log(`  [DRY RUN] POST ${path}`, JSON.stringify(body));
    return { id: `dry-run-${Date.now()}` } as T;
  }
  const res = await fetch(`${SHELF_API_URL}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${SHELF_API_SECRET}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Shelf POST ${path}: ${res.status} ${text}`);
  }
  return res.json() as Promise<T>;
}

// --- Main ---

async function main() {
  console.log(`\n=== Todoist → todo-shelf 移行 ===`);
  console.log(`Shelf API: ${SHELF_API_URL}`);
  console.log(`DRY_RUN: ${DRY_RUN}\n`);

  // 1. Todoist からデータ取得
  console.log("📥 Todoist からデータ取得中...");

  const { results: allProjects } = await todoistGet<{ results: TodoistProject[] }>("/projects");
  const projects = allProjects
    .filter((p) => TARGET_PROJECTS.includes(p.name))
    .sort((a, b) => TARGET_PROJECTS.indexOf(a.name) - TARGET_PROJECTS.indexOf(b.name));

  console.log(`  プロジェクト: ${projects.map((p) => p.name).join(", ")}`);

  const { results: allSections } = await todoistGet<{ results: TodoistSection[] }>("/sections");

  let allTasks: TodoistTask[] = [];
  for (const p of projects) {
    const { results: tasks } = await todoistGet<{ results: TodoistTask[] }>(
      `/tasks?project_id=${p.id}`
    );
    allTasks = allTasks.concat(tasks);
  }

  console.log(`  セクション: ${allSections.length}件`);
  console.log(`  タスク: ${allTasks.length}件`);

  // コメント取得（タスクごとに）
  const allComments: TodoistComment[] = [];
  for (const task of allTasks) {
    const { results: comments } = await todoistGet<{ results: TodoistComment[] }>(
      `/comments?task_id=${task.id}`
    );
    if (comments.length > 0) {
      allComments.push(...comments);
    }
  }
  console.log(`  コメント: ${allComments.length}件\n`);

  // 2. Shelf にデータ作成
  console.log("📤 todo-shelf にデータ作成中...\n");

  // ID マッピング: Todoist ID → Shelf ID
  const projectMap = new Map<string, string>();
  const sectionMap = new Map<string, string>();
  const taskMap = new Map<string, string>();

  // プロジェクト作成
  for (const p of projects) {
    console.log(`📁 プロジェクト: ${p.name}`);
    const created = await shelfPost<{ id: string }>("/projects", { name: p.name });
    projectMap.set(p.id, created.id);
  }

  // セクション作成
  for (const p of projects) {
    const sections = allSections
      .filter((s) => s.project_id === p.id)
      .sort((a, b) => a.section_order - b.section_order);

    const shelfProjectId = projectMap.get(p.id)!;
    for (const s of sections) {
      console.log(`  📂 セクション: ${s.name}`);
      const created = await shelfPost<{ id: string }>(
        `/projects/${shelfProjectId}/sections`,
        { name: s.name }
      );
      sectionMap.set(s.id, created.id);
    }
  }

  // タスク作成（セクションごとに順序を保持）
  for (const p of projects) {
    const shelfProjectId = projectMap.get(p.id)!;
    const projectTasks = allTasks
      .filter((t) => t.project_id === p.id)
      .sort((a, b) => a.child_order - b.child_order);

    for (const t of projectTasks) {
      const shelfSectionId = t.section_id ? sectionMap.get(t.section_id) ?? null : null;
      console.log(`    📝 タスク: ${t.content}`);
      const created = await shelfPost<{ id: string }>("/tasks", {
        title: t.content,
        project_id: shelfProjectId,
        section_id: shelfSectionId,
        due_date: t.due?.date ?? null,
      });
      taskMap.set(t.id, created.id);
    }
  }

  // コメント作成
  for (const c of allComments) {
    const shelfTaskId = taskMap.get(c.task_id);
    if (!shelfTaskId) continue;
    console.log(`    💬 コメント: ${c.content.slice(0, 40)}...`);
    await shelfPost(`/tasks/${shelfTaskId}/comments`, { content: c.content });
  }

  console.log(`\n✅ 移行完了!`);
  console.log(`  プロジェクト: ${projectMap.size}件`);
  console.log(`  セクション: ${sectionMap.size}件`);
  console.log(`  タスク: ${taskMap.size}件`);
  console.log(`  コメント: ${allComments.length}件`);
}

main().catch((e) => {
  console.error("❌ エラー:", e.message);
  process.exit(1);
});

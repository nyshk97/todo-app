import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { req, json, applySchema } from "./helpers";
import { materializeRecurring, nextOccurrence } from "../lib/recurrence";

type TaskRow = {
  id: string;
  project_id: string;
  section_id: string | null;
  title: string;
  due_date: string | null;
  position: number;
  archived_at: string | null;
  repeat_unit: string | null;
  repeat_interval: number | null;
  repeat_anchor_day: number | null;
};

async function createProject(name: string): Promise<string> {
  const res = await req("/projects", { method: "POST", body: { name } });
  return (await json<{ id: string }>(res)).id;
}

async function createTask(projectId: string, title: string, extra: Record<string, unknown> = {}) {
  const res = await req("/tasks", { method: "POST", body: { project_id: projectId, title, ...extra } });
  return json<TaskRow>(res);
}

async function patchTask(id: string, body: Record<string, unknown>) {
  return req(`/tasks/${id}`, { method: "PATCH", body });
}

async function getTask(id: string): Promise<TaskRow> {
  return (await env.DB.prepare("SELECT * FROM tasks WHERE id = ?").bind(id).first<TaskRow>())!;
}

beforeAll(async () => {
  await applySchema();
});

describe("nextOccurrence", () => {
  it("keeps the original day across short months", () => {
    const seq = ["2027-01-31"];
    for (let i = 0; i < 4; i++) seq.push(nextOccurrence(seq[seq.length - 1], "month", 1, 31));
    expect(seq).toEqual(["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30", "2027-05-31"]);
  });

  it("handles every N months across a year boundary", () => {
    expect(nextOccurrence("2026-11-07", "month", 3, 7)).toBe("2027-02-07");
  });

  it("handles leap days for yearly repeats", () => {
    const first = nextOccurrence("2028-02-29", "year", 1, 29);
    expect(first).toBe("2029-02-28");
    expect(nextOccurrence(first, "year", 3, 29)).toBe("2032-02-29");
  });

  it("adds days and weeks", () => {
    expect(nextOccurrence("2027-04-02", "day", 270, null)).toBe("2027-12-28");
    expect(nextOccurrence("2026-12-29", "week", 1, null)).toBe("2027-01-05");
  });
});

describe("Recurring tasks API", () => {
  let shelfId: string;
  let recurringId: string;
  let backlogId: string;

  beforeAll(async () => {
    shelfId = await createProject("Shelf");
    recurringId = await createProject("Recurring");
    backlogId = await createProject("Backlog");
  });

  it("sets a repeat on a Recurring task and remembers the day of the due date", async () => {
    const task = await createTask(recurringId, "請求書だす", { due_date: "2027-01-31" });
    const res = await patchTask(task.id, { repeat_unit: "month", repeat_interval: 1 });
    expect(res.status).toBe(200);
    const updated = await json<TaskRow>(res);
    expect(updated.repeat_unit).toBe("month");
    expect(updated.repeat_interval).toBe(1);
    expect(updated.repeat_anchor_day).toBe(31);

    // 期日を入れ直すと「何日」も入れ直す
    const res2 = await patchTask(task.id, { due_date: "2027-02-15" });
    expect((await json<TaskRow>(res2)).repeat_anchor_day).toBe(15);
  });

  it("rejects a repeat on a task outside Recurring", async () => {
    const task = await createTask(backlogId, "普通のタスク", { due_date: "2027-01-01" });
    const res = await patchTask(task.id, { repeat_unit: "month", repeat_interval: 1 });
    expect(res.status).toBe(400);
    expect((await getTask(task.id)).repeat_unit).toBeNull();
  });

  it("rejects a half-set or out-of-range repeat", async () => {
    const task = await createTask(recurringId, "半端", { due_date: "2027-01-01" });
    for (const body of [
      { repeat_unit: "month" },
      { repeat_interval: 2 },
      { repeat_unit: "month", repeat_interval: 0 },
      { repeat_unit: "month", repeat_interval: 1.5 },
      { repeat_unit: "hour", repeat_interval: 1 },
      { repeat_unit: "month", repeat_interval: null },
    ]) {
      const res = await patchTask(task.id, body);
      expect(res.status, JSON.stringify(body)).toBe(400);
    }
  });

  it("clears the repeat with nulls and when moved out of Recurring", async () => {
    const task = await createTask(recurringId, "外す", { due_date: "2027-03-10" });
    await patchTask(task.id, { repeat_unit: "year", repeat_interval: 1 });
    const cleared = await json<TaskRow>(await patchTask(task.id, { repeat_unit: null, repeat_interval: null }));
    expect([cleared.repeat_unit, cleared.repeat_interval, cleared.repeat_anchor_day]).toEqual([null, null, null]);

    await patchTask(task.id, { repeat_unit: "year", repeat_interval: 1 });
    expect((await getTask(task.id)).repeat_unit).toBe("year");
    const moved = await json<TaskRow>(await patchTask(task.id, { project_id: backlogId, section_id: null }));
    expect(moved.project_id).toBe(backlogId);
    expect([moved.repeat_unit, moved.repeat_interval, moved.repeat_anchor_day]).toEqual([null, null, null]);
  });

  it("keeps Recurring tasks out of upcoming", async () => {
    const soon = new Date(Date.now() + 9 * 3600_000).toISOString().slice(0, 10);
    const rec = await createTask(recurringId, "upcomingに出ない", { due_date: soon });
    const normal = await createTask(backlogId, "upcomingに出る", { due_date: soon });
    const list = await json<{ id: string }[]>(await req("/tasks/upcoming?days=3"));
    const ids = list.map((t) => t.id);
    expect(ids).toContain(normal.id);
    expect(ids).not.toContain(rec.id);
  });

  it("refuses move-to-today for a Recurring task", async () => {
    const task = await createTask(recurringId, "移動できない", { due_date: "2027-01-01" });
    const res = await req(`/tasks/${task.id}/move-to-today`, { method: "POST", body: {} });
    expect(res.status).toBe(400);
    expect((await getTask(task.id)).archived_at).toBeNull();
  });
});

describe("materializeRecurring", () => {
  let shelfId: string;
  let recurringId: string;
  let monthly: TaskRow;
  let existingTop: TaskRow;
  let sourceR2Key: string;

  beforeAll(async () => {
    // 他の describe とは別の DB 状態にする（プロジェクト名で引くため）
    await env.DB.prepare("DELETE FROM projects").run();
    shelfId = await createProject("Shelf");
    recurringId = await createProject("Recurring");

    existingTop = await createTask(shelfId, "もともと先頭のタスク");
    const sectionRes = await req(`/projects/${shelfId}/sections`, { method: "POST", body: { name: "S" } });
    const sectionId = (await json<{ id: string }>(sectionRes)).id;
    await createTask(shelfId, "セクションの中のタスク", { section_id: sectionId });

    monthly = await createTask(recurringId, "リンクウェルで月17日以上働きそうなら、休み取る", { due_date: "2026-10-13" });
    await patchTask(monthly.id, { repeat_unit: "month", repeat_interval: 1 });

    // コメント + 添付
    const form = new FormData();
    form.append("content", "freeeで社保等を登録して、ひろさきさんにメール");
    form.append("files", new File(["hello attachment"], "memo.txt", { type: "text/plain" }));
    const commentRes = await req(`/tasks/${monthly.id}/comments`, { method: "POST", form });
    expect(commentRes.status).toBe(201);
    sourceR2Key = (await env.DB.prepare("SELECT r2_key FROM attachments").first<{ r2_key: string }>())!.r2_key;

    // 対象外: 期日が明日 / 繰り返しなし / アーカイブ済み
    const tomorrow = await createTask(recurringId, "明日のもの", { due_date: "2026-11-02" });
    await patchTask(tomorrow.id, { repeat_unit: "day", repeat_interval: 1 });
    await createTask(recurringId, "繰り返しなし", { due_date: "2026-10-01" });
    const archived = await createTask(recurringId, "アーカイブ済み", { due_date: "2026-10-01" });
    await patchTask(archived.id, { repeat_unit: "day", repeat_interval: 1 });
    await env.DB.prepare("UPDATE tasks SET archived_at = '2026-10-02 00:00:00' WHERE id = ?").bind(archived.id).run();

    // 何回分も取りこぼした毎週のもの
    const weekly = await createTask(recurringId, "毎週のもの", { due_date: "2026-10-11" });
    await patchTask(weekly.id, { repeat_unit: "week", repeat_interval: 1 });
  });

  async function shelfUnsectioned(): Promise<TaskRow[]> {
    return (
      await env.DB.prepare(
        "SELECT * FROM tasks WHERE project_id = ? AND section_id IS NULL AND archived_at IS NULL ORDER BY position"
      )
        .bind(shelfId)
        .all<TaskRow>()
    ).results;
  }

  it("copies due tasks to the top of Shelf's unsectioned list and advances the source", async () => {
    const before = await shelfUnsectioned();
    expect(before.map((t) => t.title)).toEqual(["もともと先頭のタスク"]);

    const result = await materializeRecurring(env, "2026-11-01");
    expect(result.created.map((c) => c.dueDate).sort()).toEqual(["2026-10-11", "2026-10-13"]);

    const after = await shelfUnsectioned();
    expect(after.length).toBe(3);
    expect(after[after.length - 1].id).toBe(existingTop.id); // 既存のタスクより上に入る

    const copy = after.find((t) => t.title === monthly.title)!;
    expect(copy.due_date).toBe("2026-11-01"); // 取りこぼした回（10/13）でも今日の期日で入る
    expect(copy.section_id).toBeNull();
    expect(copy.position).toBeLessThan(existingTop.position);
    expect([copy.repeat_unit, copy.repeat_interval]).toEqual([null, null]);

    expect((await getTask(monthly.id)).due_date).toBe("2026-11-13");
    // 毎週のものは複製1件で、次回は今日より後（10/11 → 10/18 → 10/25 → 11/1 → 11/8）
    const weekly = after.find((t) => t.title === "毎週のもの")!;
    expect(weekly.due_date).toBe("2026-11-01");
    const weeklySource = await env.DB.prepare("SELECT due_date FROM tasks WHERE project_id = ? AND title = ?")
      .bind(recurringId, "毎週のもの")
      .first<{ due_date: string }>();
    expect(weeklySource!.due_date).toBe("2026-11-08");
  });

  it("copies comments and attachments into separate R2 objects", async () => {
    const copy = (await shelfUnsectioned()).find((t) => t.title === monthly.title)!;
    const comments = await json<{ content: string; attachments: { id: string; filename: string }[] }[]>(
      await req(`/tasks/${copy.id}/comments`)
    );
    expect(comments.length).toBe(1);
    expect(comments[0].content).toBe("freeeで社保等を登録して、ひろさきさんにメール");
    expect(comments[0].attachments.map((a) => a.filename)).toEqual(["memo.txt"]);

    const copyKey = (await env.DB.prepare("SELECT r2_key FROM attachments WHERE id = ?")
      .bind(comments[0].attachments[0].id)
      .first<{ r2_key: string }>())!.r2_key;
    expect(copyKey).not.toBe(sourceR2Key);
    expect(await (await env.ATTACHMENTS.get(copyKey))!.text()).toBe("hello attachment");

    // 複製を消しても元の添付は残る
    expect((await req(`/tasks/${copy.id}`, { method: "DELETE" })).status).toBe(204);
    expect(await env.ATTACHMENTS.get(copyKey)).toBeNull();
    expect(await (await env.ATTACHMENTS.get(sourceR2Key))!.text()).toBe("hello attachment");
  });

  it("does nothing more when run again on the same day", async () => {
    const before = (await env.DB.prepare("SELECT COUNT(*) as n FROM tasks").first<{ n: number }>())!.n;
    const result = await materializeRecurring(env, "2026-11-01");
    expect(result.created).toEqual([]);
    const after = (await env.DB.prepare("SELECT COUNT(*) as n FROM tasks").first<{ n: number }>())!.n;
    expect(after).toBe(before);
  });

  it("adds a separate row for the next occurrence even if the previous copy is still there", async () => {
    await materializeRecurring(env, "2026-11-08"); // 毎週のものの次の回
    const weeklyCopies = (await shelfUnsectioned()).filter((t) => t.title === "毎週のもの");
    expect(weeklyCopies.map((t) => t.due_date).sort()).toEqual(["2026-11-01", "2026-11-08"]);
  });
});

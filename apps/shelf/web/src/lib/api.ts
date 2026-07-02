const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8787";
const API_SECRET = import.meta.env.VITE_API_SECRET ?? "";

// 遅延調査用: 1秒を超えた（または失敗した）リクエストを console と localStorage に残す。
// 確認方法: devtools console で JSON.parse(localStorage.getItem("slow-requests"))
const SLOW_MS = 1000;
const SLOW_LOG_KEY = "slow-requests";

export function recordSlowRequest(entry: {
  at: string;
  method: string;
  path: string;
  ms: number;
  status: number | string;
}) {
  console.warn("[slow-request]", entry);
  try {
    const list = JSON.parse(localStorage.getItem(SLOW_LOG_KEY) ?? "[]") as unknown[];
    list.push(entry);
    localStorage.setItem(SLOW_LOG_KEY, JSON.stringify(list.slice(-50)));
  } catch {
    // localStorage が使えない環境では console のみ
  }
}

async function request<T>(path: string, init?: RequestInit & { json?: unknown }): Promise<T> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${API_SECRET}`,
    ...(init?.headers as Record<string, string>),
  };
  if (init?.json) {
    headers["Content-Type"] = "application/json";
  }
  const method = init?.method ?? "GET";
  const start = performance.now();
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      ...init,
      headers,
      body: init?.json ? JSON.stringify(init.json) : init?.body,
    });
  } catch (e) {
    recordSlowRequest({
      at: new Date().toISOString(),
      method,
      path,
      ms: Math.round(performance.now() - start),
      status: "network-error",
    });
    throw e;
  }
  const ms = Math.round(performance.now() - start);
  if (ms > SLOW_MS) {
    recordSlowRequest({ at: new Date().toISOString(), method, path, ms, status: res.status });
  }
  if (res.status === 204) return undefined as T;
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error((err as { error: string }).error);
  }
  return res.json() as Promise<T>;
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body: unknown) => request<T>(path, { method: "POST", json: body }),
  patch: <T>(path: string, body: unknown) => request<T>(path, { method: "PATCH", json: body }),
  delete: (path: string) => request<void>(path, { method: "DELETE" }),
  postForm: <T>(path: string, formData: FormData) =>
    request<T>(path, { method: "POST", body: formData }),
  attachmentUrl: (id: string) => `${API_URL}/attachments/${id}?token=${API_SECRET}`,
};

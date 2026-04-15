const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8787";
const API_SECRET = import.meta.env.VITE_API_SECRET ?? "";

async function request<T>(path: string, init?: RequestInit & { json?: unknown }): Promise<T> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${API_SECRET}`,
    ...(init?.headers as Record<string, string>),
  };
  if (init?.json) {
    headers["Content-Type"] = "application/json";
  }
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers,
    body: init?.json ? JSON.stringify(init.json) : init?.body,
  });
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

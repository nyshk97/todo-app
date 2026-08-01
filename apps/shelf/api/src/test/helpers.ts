import { env } from "cloudflare:test";
import app from "../index";

export async function req(
  path: string,
  opts?: { method?: string; body?: unknown }
): Promise<Response> {
  const init: RequestInit = { method: opts?.method ?? "GET" };
  const headers: Record<string, string> = {
    Authorization: `Bearer ${env.API_SECRET}`,
  };
  if (opts?.body) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(opts.body);
  }
  init.headers = headers;
  return app.fetch(new Request(`http://localhost${path}`, init), env);
}

export async function json<T = unknown>(res: Response): Promise<T> {
  return res.json() as Promise<T>;
}

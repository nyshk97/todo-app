import { createMiddleware } from "hono/factory";
import type { Bindings } from "../lib/db";

export const auth = createMiddleware<{ Bindings: Bindings }>(
  async (c, next) => {
    const header = c.req.header("Authorization");
    const token = new URL(c.req.url).searchParams.get("token");
    if (
      header === `Bearer ${c.env.API_SECRET}` ||
      token === c.env.API_SECRET
    ) {
      await next();
      return;
    }
    return c.json({ error: "Unauthorized" }, 401);
  }
);

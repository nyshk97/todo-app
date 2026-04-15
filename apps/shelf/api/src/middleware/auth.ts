import { createMiddleware } from "hono/factory";
import type { Bindings } from "../lib/db";

export const auth = createMiddleware<{ Bindings: Bindings }>(
  async (c, next) => {
    const header = c.req.header("Authorization");
    if (!header || header !== `Bearer ${c.env.API_SECRET}`) {
      return c.json({ error: "Unauthorized" }, 401);
    }
    await next();
  }
);

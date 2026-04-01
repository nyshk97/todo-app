import { describe, it, expect, vi, afterEach } from "vitest";
import { today, yesterday, daysAgo, isEditable } from "../date";

describe("date utilities (JST)", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  describe("today", () => {
    it("returns JST date in YYYY-MM-DD format", () => {
      vi.useFakeTimers();
      // UTC 10:00 = JST 19:00 → same day
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(today()).toBe("2026-04-01");
    });

    it("returns next day in JST when UTC is late evening", () => {
      vi.useFakeTimers();
      // UTC 23:00 Apr 1 = JST 08:00 Apr 2
      vi.setSystemTime(new Date("2026-04-01T23:00:00Z"));
      expect(today()).toBe("2026-04-02");
    });

    it("returns same day in JST when UTC is early morning", () => {
      vi.useFakeTimers();
      // UTC 00:30 Apr 1 = JST 09:30 Apr 1
      vi.setSystemTime(new Date("2026-04-01T00:30:00Z"));
      expect(today()).toBe("2026-04-01");
    });
  });

  describe("yesterday", () => {
    it("returns previous JST date", () => {
      vi.useFakeTimers();
      // UTC 10:00 Apr 1 = JST 19:00 Apr 1 → yesterday = Mar 31
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(yesterday()).toBe("2026-03-31");
    });

    it("handles month boundary", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-03-01T10:00:00Z"));
      expect(yesterday()).toBe("2026-02-28");
    });
  });

  describe("daysAgo", () => {
    it("returns 0 for today", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(daysAgo("2026-04-01")).toBe(0);
    });

    it("returns 1 for yesterday", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(daysAgo("2026-03-31")).toBe(1);
    });

    it("returns 7 for a week ago", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(daysAgo("2026-03-25")).toBe(7);
    });
  });

  describe("isEditable", () => {
    it("today is editable", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(isEditable("2026-04-01")).toBe(true);
    });

    it("yesterday is editable", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(isEditable("2026-03-31")).toBe(true);
    });

    it("2 days ago is NOT editable", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(isEditable("2026-03-30")).toBe(false);
    });
  });
});

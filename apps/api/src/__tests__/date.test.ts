import { describe, it, expect, vi, afterEach } from "vitest";
import { today, yesterday, daysAgo, isEditable } from "../date";

describe("date utilities", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  describe("today", () => {
    it("returns current date in YYYY-MM-DD format", () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date("2026-04-01T10:00:00Z"));
      expect(today()).toBe("2026-04-01");
    });
  });

  describe("yesterday", () => {
    it("returns previous date", () => {
      vi.useFakeTimers();
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

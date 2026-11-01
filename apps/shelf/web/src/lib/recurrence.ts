import type { RepeatUnit } from "@todo-shelf/shared";

/** 繰り返しタスクの置き場。API の cron もこの名前で引くので、変えるときは API と DB も一緒に変える */
export const RECURRING_PROJECT_NAME = "Recurring";

export const REPEAT_UNITS: { value: RepeatUnit; label: string }[] = [
  { value: "day", label: "日ごと" },
  { value: "week", label: "週ごと" },
  { value: "month", label: "か月ごと" },
  { value: "year", label: "年ごと" },
];

export function repeatLabel(unit: RepeatUnit, interval: number): string {
  if (interval === 1) {
    return { day: "毎日", week: "毎週", month: "毎月", year: "毎年" }[unit];
  }
  return { day: `${interval}日ごと`, week: `${interval}週間ごと`, month: `${interval}か月ごと`, year: `${interval}年ごと` }[unit];
}

function toJST(date: Date): Date {
  return new Date(date.getTime() + 9 * 60 * 60 * 1000);
}

function formatDate(date: Date): string {
  return toJST(date).toISOString().slice(0, 10);
}

export function today(): string {
  return formatDate(new Date());
}

export function yesterday(): string {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  return formatDate(d);
}

export function daysAgo(date: string): number {
  const now = new Date(today());
  const target = new Date(date);
  return Math.floor((now.getTime() - target.getTime()) / (1000 * 60 * 60 * 24));
}

export function isEditable(date: string): boolean {
  return daysAgo(date) <= 1;
}

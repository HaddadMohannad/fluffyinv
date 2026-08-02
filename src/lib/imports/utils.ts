export function parseNumber(value: string | undefined): number | null {
  if (value === undefined) return null;
  const cleaned = value.replace(/[^0-9.-]/g, "").trim();
  if (cleaned === "") return null;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}

export function parseDate(value: string | undefined): string | null {
  if (!value || value.trim() === "") return null;
  const d = new Date(value.trim());
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

export function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

// Validated palette (see dataviz skill / references/palette.md). Assigned
// by entity identity in fixed order — never regenerated or reassigned by
// rank — and re-stepped for the dark chart surface as a set, not a flip.
export const CATEGORICAL_LIGHT = [
  "#2a78d6",
  "#eb6834",
  "#1baf7a",
  "#eda100",
  "#e87ba4",
  "#008300",
  "#4a3aa7",
  "#e34948",
];
export const CATEGORICAL_DARK = [
  "#3987e5",
  "#d95926",
  "#199e70",
  "#c98500",
  "#d55181",
  "#008300",
  "#9085e9",
  "#e66767",
];

// Fixed status roles — reserved for state, never reused as a series color.
// Same steps in both modes (each already clears 3:1 on both surfaces).
export const STATUS_COLORS = {
  good: "#0ca30c",
  warning: "#fab219",
  critical: "#d03b3b",
};

export const CHART_INK_LIGHT = {
  primary: "#0b0b0b",
  secondary: "#52514e",
  muted: "#898781",
  gridline: "#e1e0d9",
  baseline: "#c3c2b7",
};
export const CHART_INK_DARK = {
  primary: "#ffffff",
  secondary: "#c3c2b7",
  muted: "#898781",
  gridline: "#2c2c2a",
  baseline: "#383835",
};

export function categoricalColor(index: number, isDark: boolean) {
  const ramp = isDark ? CATEGORICAL_DARK : CATEGORICAL_LIGHT;
  return ramp[index % ramp.length];
}

export function statusColorForPct(pct: number | null) {
  if (pct === null) return STATUS_COLORS.critical;
  if (pct >= 90) return STATUS_COLORS.good;
  if (pct >= 80) return STATUS_COLORS.warning;
  return STATUS_COLORS.critical;
}

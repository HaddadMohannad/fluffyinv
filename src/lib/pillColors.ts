export type PillTone =
  | "blue"
  | "orange"
  | "green"
  | "red"
  | "yellow"
  | "amber"
  | "zinc";

// Shared color mappings so category/status/activity-type colors stay
// consistent wherever they're used, instead of being redefined per page.
export function categoryTone(type: string): PillTone {
  if (type === "raw") return "blue";
  if (type === "processed") return "orange";
  if (type === "sellable") return "green";
  return "zinc";
}

export function statusTone(status: string): PillTone {
  if (status === "approved" || status === "completed") return "green";
  if (status === "pending" || status === "in_transit") return "blue";
  if (status === "rejected" || status === "cancelled") return "red";
  return "zinc";
}

export function activityTypeTone(type: string): PillTone {
  if (type === "transfer") return "blue";
  if (type === "waste") return "red";
  if (type === "hospitality") return "yellow";
  if (type === "production") return "green";
  return "zinc";
}

import type { ReactNode } from "react";
import type { PillTone } from "@/lib/pillColors";

const TONE_CLASSES: Record<PillTone, string> = {
  blue: "bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-300",
  orange:
    "bg-orange-100 text-orange-700 dark:bg-orange-950 dark:text-orange-300",
  green: "bg-green-100 text-green-700 dark:bg-green-950 dark:text-green-300",
  red: "bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-300",
  yellow:
    "bg-yellow-100 text-yellow-700 dark:bg-yellow-950 dark:text-yellow-300",
  amber: "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300",
  zinc: "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300",
};

export function Pill({ tone, children }: { tone: PillTone; children: ReactNode }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${TONE_CLASSES[tone]}`}
    >
      {children}
    </span>
  );
}

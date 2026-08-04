import type { LucideIcon } from "lucide-react";

type Delta = { value: string; direction: "up" | "down" };

export function StatCard({
  label,
  value,
  icon: Icon,
  delta,
}: {
  label: string;
  value: string | number;
  icon?: LucideIcon;
  delta?: Delta;
}) {
  return (
    <div className="rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900">
      <div className="flex items-center justify-between">
        <span className="text-sm text-zinc-500 dark:text-zinc-400">{label}</span>
        {Icon && <Icon className="h-4 w-4 text-zinc-400 dark:text-zinc-500" />}
      </div>
      <p className="text-fluffy-dark mt-1 text-2xl font-bold dark:text-zinc-50">
        {value}
      </p>
      {delta && (
        <p
          className={`mt-1 text-xs font-medium ${
            delta.direction === "up" ? "text-green-600" : "text-red-600"
          }`}
        >
          {delta.direction === "up" ? "↑" : "↓"} {delta.value}
        </p>
      )}
    </div>
  );
}

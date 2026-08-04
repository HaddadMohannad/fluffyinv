import { useEffect, useState } from "react";
import { ArrowRight, Building2, Warehouse } from "lucide-react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";

const ACCENTS = [
  {
    border: "border-t-orange-400",
    badge: "bg-orange-100 text-orange-600 dark:bg-orange-950 dark:text-orange-300",
  },
  {
    border: "border-t-blue-400",
    badge: "bg-blue-100 text-blue-600 dark:bg-blue-950 dark:text-blue-300",
  },
  {
    border: "border-t-green-400",
    badge: "bg-green-100 text-green-600 dark:bg-green-950 dark:text-green-300",
  },
  {
    border: "border-t-purple-400",
    badge: "bg-purple-100 text-purple-600 dark:bg-purple-950 dark:text-purple-300",
  },
  {
    border: "border-t-pink-400",
    badge: "bg-pink-100 text-pink-600 dark:bg-pink-950 dark:text-pink-300",
  },
  {
    border: "border-t-teal-400",
    badge: "bg-teal-100 text-teal-600 dark:bg-teal-950 dark:text-teal-300",
  },
];

function today() {
  return new Date().toISOString().slice(0, 10);
}

export function BranchSelectionPage({
  onSelect,
}: {
  onSelect: (locationId: string) => void;
}) {
  const { t, locale } = useLocale();
  const { locations } = useActiveLocation();
  const [salesByLocation, setSalesByLocation] = useState<
    Record<string, number>
  >({});

  useEffect(() => {
    supabase
      .from("sales_orders")
      .select("location_id, net")
      .eq("order_date", today())
      .then(({ data }) => {
        const map: Record<string, number> = {};
        for (const row of data ?? []) {
          map[row.location_id] = (map[row.location_id] ?? 0) + row.net;
        }
        setSalesByLocation(map);
      });
  }, []);

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.branchSelectionTitle}
      </h1>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {locations.map((loc, i) => {
          const accent = ACCENTS[i % ACCENTS.length];
          const Icon = loc.type === "warehouse" ? Warehouse : Building2;
          const name = locale === "ar" ? loc.name_ar : loc.name_en;
          const typeLabel =
            loc.type === "warehouse" ? t.warehouseTypeLabel : t.branchTypeLabel;
          return (
            <button
              key={loc.id}
              type="button"
              onClick={() => onSelect(loc.id)}
              className={`flex flex-col gap-3 rounded-xl border border-t-4 border-zinc-200 bg-white p-4 text-start shadow-sm transition hover:shadow-md dark:border-zinc-800 dark:bg-zinc-900 ${accent.border}`}
            >
              <div className="flex items-center justify-between">
                <span
                  className={`flex h-10 w-10 items-center justify-center rounded-lg ${accent.badge}`}
                >
                  <Icon className="h-5 w-5" />
                </span>
                <ArrowRight className="h-4 w-4 text-zinc-400 rtl:rotate-180" />
              </div>
              <div>
                <p className="text-fluffy-dark font-semibold dark:text-zinc-50">
                  {name}
                </p>
                <p className="text-xs text-zinc-500 dark:text-zinc-400">
                  {loc.city ?? typeLabel}
                </p>
              </div>
              <span className="bg-fluffy-orange/10 text-fluffy-orange w-fit rounded-full px-2.5 py-0.5 text-xs font-medium">
                {t.todaysSalesLabel}: {(salesByLocation[loc.id] ?? 0).toFixed(2)}{" "}
                JOD
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

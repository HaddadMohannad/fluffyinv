import { useEffect, useMemo, useState } from "react";
import { Boxes, Heart, ShoppingCart, Trash2 } from "lucide-react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import { StatCard } from "@/components/StatCard";
import { Pill } from "@/components/Pill";
import { activityTypeTone } from "@/lib/pillColors";
import type { Tables } from "@/lib/supabase/database.types";

const ACTIVITY_MOVEMENTS = [
  "transfer_in",
  "transfer_out",
  "waste",
  "hospitality",
  "production_in",
] as const;

type ActivityRow = Pick<
  Tables<"stock_ledger">,
  "id" | "product_id" | "qty" | "movement" | "created_at"
>;

function dateStr(daysAgo: number) {
  const d = new Date();
  d.setDate(d.getDate() - daysAgo);
  return d.toISOString().slice(0, 10);
}

function startOfDayIso(daysAgo: number) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - daysAgo);
  return d.toISOString();
}

function activityType(
  movement: string
): "transfer" | "waste" | "hospitality" | "production" {
  if (movement === "transfer_in" || movement === "transfer_out")
    return "transfer";
  if (movement === "production_in") return "production";
  return movement === "hospitality" ? "hospitality" : "waste";
}

function formatMoney(n: number) {
  return `${n.toFixed(2)} JOD`;
}

export function DashboardPage() {
  const { t, locale } = useLocale();
  const { locationId, locations } = useActiveLocation();

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [stockQty, setStockQty] = useState<Record<string, number>>({});
  const [todayLedgerQty, setTodayLedgerQty] = useState<Record<string, number>>(
    {}
  );
  const [recentActivity, setRecentActivity] = useState<ActivityRow[]>([]);
  const [todaysSales, setTodaysSales] = useState(0);
  const [yesterdaysSales, setYesterdaysSales] = useState(0);
  const [wasteToday, setWasteToday] = useState(0);
  const [wasteYesterday, setWasteYesterday] = useState(0);
  const [hospitalityToday, setHospitalityToday] = useState(0);
  const [hospitalityYesterday, setHospitalityYesterday] = useState(0);

  useEffect(() => {
    supabase
      .from("products")
      .select("*")
      .then(({ data }) => setProducts(data ?? []));
  }, []);

  useEffect(() => {
    if (!locationId) return;

    supabase
      .from("v_current_stock")
      .select("product_id, qty")
      .eq("location_id", locationId)
      .then(({ data }) => {
        const map: Record<string, number> = {};
        for (const row of data ?? []) {
          if (row.product_id !== null && row.qty !== null) {
            map[row.product_id] = row.qty;
          }
        }
        setStockQty(map);
      });

    supabase
      .from("stock_ledger")
      .select("product_id, qty")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(0))
      .then(({ data }) => {
        const map: Record<string, number> = {};
        for (const row of data ?? []) {
          map[row.product_id] = (map[row.product_id] ?? 0) + row.qty;
        }
        setTodayLedgerQty(map);
      });

    supabase
      .from("stock_ledger")
      .select("id, product_id, qty, movement, created_at")
      .eq("location_id", locationId)
      .in("movement", ACTIVITY_MOVEMENTS)
      .order("created_at", { ascending: false })
      .limit(15)
      .then(({ data }) => setRecentActivity(data ?? []));

    supabase
      .from("sales_orders")
      .select("net")
      .eq("location_id", locationId)
      .eq("order_date", dateStr(0))
      .then(({ data }) => {
        setTodaysSales((data ?? []).reduce((sum, r) => sum + r.net, 0));
      });
    supabase
      .from("sales_orders")
      .select("net")
      .eq("location_id", locationId)
      .eq("order_date", dateStr(1))
      .then(({ data }) => {
        setYesterdaysSales((data ?? []).reduce((sum, r) => sum + r.net, 0));
      });

    supabase
      .from("waste_records")
      .select("value_lost")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(0))
      .then(({ data }) => {
        setWasteToday((data ?? []).reduce((sum, r) => sum + r.value_lost, 0));
      });
    supabase
      .from("waste_records")
      .select("value_lost")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(1))
      .lt("created_at", startOfDayIso(0))
      .then(({ data }) => {
        setWasteYesterday(
          (data ?? []).reduce((sum, r) => sum + r.value_lost, 0)
        );
      });

    supabase
      .from("hospitality_records")
      .select("value")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(0))
      .then(({ data }) => {
        setHospitalityToday((data ?? []).reduce((sum, r) => sum + r.value, 0));
      });
    supabase
      .from("hospitality_records")
      .select("value")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(1))
      .lt("created_at", startOfDayIso(0))
      .then(({ data }) => {
        setHospitalityYesterday(
          (data ?? []).reduce((sum, r) => sum + r.value, 0)
        );
      });
  }, [locationId]);

  const avgCostByProduct = useMemo(
    () => new Map(products.map((p) => [p.id, p.avg_cost])),
    [products]
  );

  // Yesterday's stock value is derived from today's value minus today's net
  // ledger movement, both priced at the current avg_cost -- the ledger only
  // records per-movement cost, not a historical valuation snapshot.
  const stockValueToday = useMemo(() => {
    let total = 0;
    for (const [productId, qty] of Object.entries(stockQty)) {
      total += qty * (avgCostByProduct.get(productId) ?? 0);
    }
    return total;
  }, [stockQty, avgCostByProduct]);

  const stockValueYesterday = useMemo(() => {
    let total = 0;
    for (const [productId, qty] of Object.entries(stockQty)) {
      const yesterdayQty = qty - (todayLedgerQty[productId] ?? 0);
      total += yesterdayQty * (avgCostByProduct.get(productId) ?? 0);
    }
    return total;
  }, [stockQty, todayLedgerQty, avgCostByProduct]);

  function makeDelta(current: number, previous: number, invert = false) {
    const diff = current - previous;
    if (diff === 0) return undefined;
    const increased = diff > 0;
    return {
      value: `${formatMoney(Math.abs(diff))} ${t.vsYesterday}`,
      direction: (increased !== invert ? "up" : "down") as "up" | "down",
    };
  }

  const productName = useMemo(
    () =>
      new Map(
        products.map((p) => [p.id, locale === "ar" ? p.name_ar : p.name_en])
      ),
    [products, locale]
  );

  const activeLocationName = useMemo(() => {
    const loc = locations.find((l) => l.id === locationId);
    return loc ? (locale === "ar" ? loc.name_ar : loc.name_en) : "";
  }, [locations, locationId, locale]);

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.dashboardTitle}
      </h1>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label={t.totalStockValueLabel}
          value={formatMoney(stockValueToday)}
          icon={Boxes}
          delta={makeDelta(stockValueToday, stockValueYesterday)}
        />
        <StatCard
          label={t.todaysSalesLabel}
          value={formatMoney(todaysSales)}
          icon={ShoppingCart}
          delta={makeDelta(todaysSales, yesterdaysSales)}
        />
        <StatCard
          label={t.wasteTodayLabel}
          value={formatMoney(wasteToday)}
          icon={Trash2}
          delta={makeDelta(wasteToday, wasteYesterday, true)}
        />
        <StatCard
          label={t.hospitalityTodayLabel}
          value={formatMoney(hospitalityToday)}
          icon={Heart}
          delta={makeDelta(hospitalityToday, hospitalityYesterday, true)}
        />
      </div>

      <section>
        <h2 className="mb-2 text-lg font-semibold">{t.recentActivityTitle}</h2>
        {recentActivity.length === 0 ? (
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.noRecentActivity}
          </p>
        ) : (
          <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.activityTypeColumn}</th>
                  <th className="p-2 text-start">{t.product}</th>
                  <th className="p-2 text-end">{t.quantity}</th>
                  <th className="p-2 text-start">{t.location}</th>
                  <th className="p-2 text-start">{t.dateColumn}</th>
                </tr>
              </thead>
              <tbody>
                {recentActivity.map((row) => {
                  const type = activityType(row.movement);
                  const label =
                    type === "transfer"
                      ? t.transfer
                      : type === "production"
                        ? t.production
                        : type === "hospitality"
                          ? t.hospitality
                          : t.waste;
                  return (
                    <tr
                      key={row.id}
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="p-2">
                        <Pill tone={activityTypeTone(type)}>{label}</Pill>
                      </td>
                      <td className="p-2">
                        {productName.get(row.product_id) ?? row.product_id}
                      </td>
                      <td className="p-2 text-end">{Math.abs(row.qty)}</td>
                      <td className="p-2">{activeLocationName}</td>
                      <td className="p-2">{row.created_at.slice(0, 10)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}

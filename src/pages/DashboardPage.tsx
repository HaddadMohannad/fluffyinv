import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router";
import { Boxes, ClipboardCheck, Heart, ShoppingCart, Trash2 } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import { StatCard } from "@/components/StatCard";
import { Pill } from "@/components/Pill";
import { activityTypeTone } from "@/lib/pillColors";
import type { PillTone } from "@/lib/pillColors";
import type { Enums, Tables } from "@/lib/supabase/database.types";

type VisitScore = Tables<"v_audit_visit_scores">;
type CorrectiveAction = Tables<"corrective_actions">;

function classificationTone(classification: string | null): PillTone {
  if (classification === "ممتاز") return "green";
  if (classification === "يحتاج تحسين") return "amber";
  if (classification === "يحتاج تدخل إداري") return "red";
  return "zinc";
}

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
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locationId, locations } = useActiveLocation();

  const canStartAudit =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "inspector";

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
  const [salesBySource, setSalesBySource] = useState<
    { source: Enums<"sales_source">; net: number }[]
  >([]);
  const [auditVisits, setAuditVisits] = useState<VisitScore[]>([]);
  const [openActions, setOpenActions] = useState<CorrectiveAction[]>([]);

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

    supabase
      .from("sales_orders")
      .select("source, net")
      .eq("location_id", locationId)
      .gte("order_date", dateStr(29))
      .then(({ data }) => {
        const map = new Map<Enums<"sales_source">, number>();
        for (const row of data ?? []) {
          map.set(row.source, (map.get(row.source) ?? 0) + row.net);
        }
        setSalesBySource(
          Array.from(map.entries())
            .map(([source, net]) => ({ source, net }))
            .sort((a, b) => b.net - a.net)
        );
      });

    supabase
      .from("v_audit_visit_scores")
      .select("*")
      .eq("location_id", locationId)
      .order("visit_date", { ascending: false })
      .limit(5)
      .then(({ data }) => setAuditVisits(data ?? []));

    supabase
      .from("corrective_actions")
      .select("*")
      .eq("location_id", locationId)
      .neq("status", "closed")
      .order("due_date", { ascending: true, nullsFirst: false })
      .limit(5)
      .then(({ data }) => setOpenActions(data ?? []));
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

  const lowStockProducts = useMemo(
    () =>
      products.filter(
        (p) =>
          p.active &&
          p.reorder_threshold !== null &&
          (stockQty[p.id] ?? 0) < p.reorder_threshold
      ),
    [products, stockQty]
  );

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

      <div className="grid gap-6 lg:grid-cols-2">
        <section>
          <h2 className="mb-2 text-lg font-semibold">
            {t.salesBySourceTitle}
          </h2>
          {salesBySource.length === 0 ? (
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              {t.noResults}
            </p>
          ) : (
            <div className="flex flex-col gap-2">
              {salesBySource.map((s) => (
                <div
                  key={s.source}
                  className="flex items-center justify-between rounded-md border border-zinc-200 p-2 text-sm dark:border-zinc-800"
                >
                  <span className="capitalize">{s.source}</span>
                  <span className="font-medium">{formatMoney(s.net)}</span>
                </div>
              ))}
            </div>
          )}
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold">
            {t.inventorySnapshotTitle} — {t.lowStockTitle}
          </h2>
          {lowStockProducts.length === 0 ? (
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              {t.noLowStockItems}
            </p>
          ) : (
            <div className="flex flex-col gap-2">
              {lowStockProducts.map((p) => (
                <div
                  key={p.id}
                  className="flex items-center justify-between rounded-md border border-amber-300 bg-amber-50 p-2 text-sm dark:border-amber-800 dark:bg-amber-950/40"
                >
                  <span>{locale === "ar" ? p.name_ar : p.name_en}</span>
                  <span className="font-medium">
                    {(stockQty[p.id] ?? 0).toFixed(1)} / {p.reorder_threshold}
                  </span>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>

      <section>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="text-lg font-semibold">{t.branchQualityTitle}</h2>
          {canStartAudit && (
            <Link
              to="/audit-entry"
              className="bg-fluffy-orange flex h-9 items-center gap-1 rounded-md px-3 text-sm font-medium text-white"
            >
              <ClipboardCheck className="h-4 w-4" />
              {t.startAuditAction}
            </Link>
          )}
        </div>

        <div className="grid gap-6 lg:grid-cols-2">
          <div>
            <div className="mb-2 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-zinc-600 dark:text-zinc-400">
                {t.recentAuditVisitsTitle}
              </h3>
              <Link
                to="/quality-dashboard"
                className="text-fluffy-orange text-xs font-medium"
              >
                {t.viewAllAction}
              </Link>
            </div>
            {auditVisits.length === 0 ? (
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                {t.noRecentAuditVisits}
              </p>
            ) : (
              <div className="flex flex-col gap-2">
                {auditVisits.map((v) => (
                  <Link
                    key={v.visit_id}
                    to={`/audit-visit/${v.visit_id}`}
                    className="flex items-center justify-between rounded-md border border-zinc-200 p-2 text-sm dark:border-zinc-800"
                  >
                    <span>{v.visit_date}</span>
                    <div className="flex items-center gap-2">
                      {v.overall_pct !== null && <span>{v.overall_pct}%</span>}
                      {v.classification && (
                        <Pill tone={classificationTone(v.classification)}>
                          {v.classification === "ممتاز"
                            ? t.excellentCountLabel
                            : v.classification === "يحتاج تحسين"
                              ? t.needsImprovementCountLabel
                              : t.needsInterventionCountLabel}
                        </Pill>
                      )}
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-zinc-600 dark:text-zinc-400">
                {t.openCorrectiveActionsTitle}
              </h3>
              <Link
                to="/corrective-actions"
                className="text-fluffy-orange text-xs font-medium"
              >
                {t.viewAllAction}
              </Link>
            </div>
            {openActions.length === 0 ? (
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                {t.noOpenCorrectiveActions}
              </p>
            ) : (
              <div className="flex flex-col gap-2">
                {openActions.map((a) => (
                  <div
                    key={a.id}
                    className="flex items-center justify-between rounded-md border border-zinc-200 p-2 text-sm dark:border-zinc-800"
                  >
                    <span>{a.description}</span>
                    {a.due_date && (
                      <span className="text-xs text-zinc-500">
                        {a.due_date}
                      </span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </section>

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

import { useEffect, useMemo, useState } from "react";
import { Layers, Package, Percent, Wallet } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { StatCard } from "@/components/StatCard";
import { CreateBatchModal } from "@/components/CreateBatchModal";

type Batch = Tables<"production_batches">;

const YIELD_GOOD_THRESHOLD = 85;

export function ProductionPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locationId } = useActiveLocation();

  const canWrite = profile?.role === "admin" || profile?.role === "warehouse_staff";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [batches, setBatches] = useState<Batch[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);
  const [showCreateModal, setShowCreateModal] = useState(false);

  useEffect(() => {
    if (!canWrite) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .in("type", ["raw", "processed"])
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canWrite]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived list when location is unset
      setBatches([]);
      return;
    }
    supabase
      .from("production_batches")
      .select("*")
      .eq("location_id", locationId)
      .order("created_at", { ascending: false })
      .limit(20)
      .then(({ data }) => setBatches(data ?? []));
  }, [locationId, refreshKey]);

  const productName = useMemo(() => {
    const map = new Map(
      products.map((p) => [p.id, locale === "ar" ? p.name_ar : p.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [products, locale]);

  const stats = useMemo(() => {
    const totalInput = batches.reduce((sum, b) => sum + b.input_qty, 0);
    const totalOutput = batches.reduce((sum, b) => sum + b.output_qty, 0);
    const totalCost = batches.reduce((sum, b) => sum + b.total_cost, 0);
    const yields = batches
      .map((b) => b.yield_pct)
      .filter((y): y is number => y !== null);
    const avgYield =
      yields.length > 0
        ? yields.reduce((sum, y) => sum + y, 0) / yields.length
        : null;
    return { totalInput, totalOutput, totalCost, avgYield };
  }, [batches]);

  if (!canWrite) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function handleSaved() {
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.productionTitle}
        </h1>
        <button
          type="button"
          disabled={!locationId}
          onClick={() => setShowCreateModal(true)}
          className="bg-fluffy-orange h-9 rounded-md px-4 text-sm font-medium text-white disabled:opacity-60"
        >
          {t.createBatchAction}
        </button>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label={t.totalInputLabel} value={stats.totalInput} icon={Layers} />
        <StatCard
          label={t.totalOutputLabel}
          value={stats.totalOutput}
          icon={Package}
        />
        <StatCard
          label={t.totalCostLabel}
          value={stats.totalCost.toFixed(2)}
          icon={Wallet}
        />
        <StatCard
          label={t.avgYieldLabel}
          value={stats.avgYield !== null ? `${stats.avgYield.toFixed(1)}%` : "—"}
          icon={Percent}
        />
      </div>

      {locationId && (
        <section>
          <h2 className="mb-2 text-lg font-semibold">{t.recentBatchesTitle}</h2>
          {batches.length === 0 ? (
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              {t.noRecentBatches}
            </p>
          ) : (
            <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              <table className="w-full min-w-max text-sm">
                <thead className="bg-zinc-50 dark:bg-zinc-900">
                  <tr>
                    <th className="p-2 text-start">{t.inputProductLabel}</th>
                    <th className="p-2 text-start">{t.outputProductLabel}</th>
                    <th className="p-2 text-end">{t.totalCostLabel}</th>
                    <th className="p-2 text-end">{t.costPerUnitLabel}</th>
                    <th className="p-2 text-end">{t.yieldLabel}</th>
                    <th className="p-2 text-start">{t.dateColumn}</th>
                  </tr>
                </thead>
                <tbody>
                  {batches.map((batch) => (
                    <tr
                      key={batch.id}
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="p-2">
                        {productName(batch.input_product_id)} ({batch.input_qty})
                      </td>
                      <td className="p-2">
                        {productName(batch.output_product_id)} (
                        {batch.output_qty})
                      </td>
                      <td className="p-2 text-end">{batch.total_cost}</td>
                      <td className="p-2 text-end">
                        {(batch.total_cost / batch.output_qty).toFixed(3)}
                      </td>
                      <td className="p-2 text-end">
                        {batch.yield_pct !== null ? (
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                              batch.yield_pct >= YIELD_GOOD_THRESHOLD
                                ? "bg-green-100 text-green-700 dark:bg-green-950 dark:text-green-300"
                                : "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300"
                            }`}
                          >
                            {batch.yield_pct}%
                          </span>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td className="p-2">
                        {new Date(batch.created_at).toLocaleDateString()}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      {showCreateModal && (
        <CreateBatchModal
          onClose={() => setShowCreateModal(false)}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}

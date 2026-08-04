import { useEffect, useMemo, useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const PERIOD_DAYS = 7;

const CONSUMPTION_MOVEMENTS = ["waste", "hospitality", "transfer_out"] as const;

export function ConsumptionReportPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locationId } = useActiveLocation();

  const canView =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "warehouse_staff";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [stock, setStock] = useState<Record<string, number>>({});
  const [consumed, setConsumed] = useState<Record<string, number>>({});
  const [sold, setSold] = useState<Record<string, number>>({});

  useEffect(() => {
    if (!canView) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canView]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when location is unset
      setStock({});
      setConsumed({});
      setSold({});
      return;
    }

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
        setStock(map);
      });

    const periodStart = new Date();
    periodStart.setDate(periodStart.getDate() - PERIOD_DAYS);

    supabase
      .from("stock_ledger")
      .select("product_id, qty")
      .eq("location_id", locationId)
      .in("movement", CONSUMPTION_MOVEMENTS)
      .gte("created_at", periodStart.toISOString())
      .then(({ data }) => {
        const map: Record<string, number> = {};
        for (const row of data ?? []) {
          map[row.product_id] = (map[row.product_id] ?? 0) + Math.abs(row.qty);
        }
        setConsumed(map);
      });

    const periodStartDate = periodStart.toISOString().slice(0, 10);
    supabase
      .from("sales_orders")
      .select("id")
      .eq("location_id", locationId)
      .gte("order_date", periodStartDate)
      .then(({ data }) => {
        const orderIds = (data ?? []).map((o) => o.id);
        if (orderIds.length === 0) {
          setSold({});
          return;
        }
        supabase
          .from("sales_lines")
          .select("product_id, qty")
          .in("order_id", orderIds)
          .then(({ data: lines }) => {
            const map: Record<string, number> = {};
            for (const row of lines ?? []) {
              if (row.product_id) {
                map[row.product_id] = (map[row.product_id] ?? 0) + row.qty;
              }
            }
            setSold(map);
          });
      });
  }, [locationId]);

  const reorderSuggestions = useMemo(
    () =>
      products
        .filter((p) => p.reorder_threshold !== null)
        .map((p) => ({
          product: p,
          currentQty: stock[p.id] ?? 0,
          suggested: (p.reorder_threshold ?? 0) - (stock[p.id] ?? 0),
        }))
        .filter((r) => r.suggested > 0),
    [products, stock]
  );

  if (!canView) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.consumptionReportTitle}
      </h1>

      {reorderSuggestions.length > 0 && (
        <section>
          <h2 className="mb-2 text-lg font-semibold">
            {t.reorderSuggestionsTitle}
          </h2>
          <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.product}</th>
                  <th className="p-2 text-end">{t.currentQtyColumn}</th>
                  <th className="p-2 text-end">{t.reorderThresholdColumn}</th>
                  <th className="p-2 text-end">{t.suggestedReorderColumn}</th>
                </tr>
              </thead>
              <tbody>
                {reorderSuggestions.map((r) => (
                  <tr
                    key={r.product.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">
                      {locale === "ar" ? r.product.name_ar : r.product.name_en}
                    </td>
                    <td className="p-2 text-end">{r.currentQty}</td>
                    <td className="p-2 text-end">{r.product.reorder_threshold}</td>
                    <td className="p-2 text-end font-medium text-amber-600">
                      {r.suggested}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      <section>
        <h2 className="mb-2 text-lg font-semibold">
          {t.consumptionVsSoldTitle}
        </h2>
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.product}</th>
                <th className="p-2 text-end">{t.consumedColumn}</th>
                <th className="p-2 text-end">{t.soldQtyColumn}</th>
                <th className="p-2 text-end">{t.currentQtyColumn}</th>
              </tr>
            </thead>
            <tbody>
              {products
                .filter(
                  (p) =>
                    (consumed[p.id] ?? 0) !== 0 ||
                    (sold[p.id] ?? 0) !== 0 ||
                    (stock[p.id] ?? 0) !== 0
                )
                .map((p) => (
                  <tr
                    key={p.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">
                      {locale === "ar" ? p.name_ar : p.name_en}
                    </td>
                    <td className="p-2 text-end">{consumed[p.id] ?? 0}</td>
                    <td className="p-2 text-end">{sold[p.id] ?? 0}</td>
                    <td className="p-2 text-end">{stock[p.id] ?? 0}</td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

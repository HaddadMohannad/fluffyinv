import { useEffect, useMemo, useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type Stocktake = Tables<"stocktakes">;
type StocktakeLine = Tables<"v_stocktake_lines">;
type StocktakeSummary = Tables<"v_stocktake_summary">;
type PendingApproval = Stocktake & { lines: StocktakeLine[] };

export function StocktakePage() {
  const { profile } = useAuth();
  const { t } = useLocale();
  const { locations, locationId } = useActiveLocation();

  const canCount =
    profile?.role === "admin" || profile?.role === "branch_manager";
  const isAdmin = profile?.role === "admin";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [activeStocktake, setActiveStocktake] = useState<Stocktake | null>(
    null
  );
  const [lines, setLines] = useState<StocktakeLine[]>([]);
  const [counts, setCounts] = useState<Record<string, string>>({});
  const [starting, setStarting] = useState(false);
  const [saving, setSaving] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const [pendingApprovals, setPendingApprovals] = useState<PendingApproval[]>(
    []
  );
  const [approvingId, setApprovingId] = useState<string | null>(null);
  const [summary, setSummary] = useState<StocktakeSummary[]>([]);

  useEffect(() => {
    if (!canCount) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .in("type", ["raw", "processed"])
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canCount]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when location is unset
      setActiveStocktake(null);
      return;
    }
    supabase
      .from("stocktakes")
      .select("*")
      .eq("location_id", locationId)
      .eq("status", "draft")
      .maybeSingle()
      .then(({ data }) => setActiveStocktake(data));
  }, [locationId, refreshKey]);

  useEffect(() => {
    if (!activeStocktake) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when there is no active session
      setLines([]);
      setCounts({});
      return;
    }
    supabase
      .from("v_stocktake_lines")
      .select("*")
      .eq("stocktake_id", activeStocktake.id)
      .then(({ data }) => {
        const rows = data ?? [];
        setLines(rows);
        const initial: Record<string, string> = {};
        for (const row of rows) {
          if (row.product_id) {
            initial[row.product_id] =
              row.counted_qty !== null ? row.counted_qty.toString() : "";
          }
        }
        setCounts(initial);
      });
  }, [activeStocktake, refreshKey]);

  useEffect(() => {
    if (!isAdmin) return;
    supabase
      .from("stocktakes")
      .select("*")
      .eq("status", "submitted")
      .order("started_at", { ascending: false })
      .then(async ({ data }) => {
        const drafts = data ?? [];
        const withLines = await Promise.all(
          drafts.map(async (st) => {
            const { data: lineData } = await supabase
              .from("v_stocktake_lines")
              .select("*")
              .eq("stocktake_id", st.id);
            const sorted = (lineData ?? []).sort(
              (a, b) =>
                Math.abs((b.variance ?? 0) * (b.unit_cost ?? 0)) -
                Math.abs((a.variance ?? 0) * (a.unit_cost ?? 0))
            );
            return { ...st, lines: sorted };
          })
        );
        setPendingApprovals(withLines);
      });
    supabase
      .from("v_stocktake_summary")
      .select("*")
      .order("started_at", { ascending: false })
      .limit(20)
      .then(({ data }) => setSummary(data ?? []));
  }, [isAdmin, refreshKey]);

  const productName = useMemo(() => {
    const map = new Map(products.map((p) => [p.id, p.name_en]));
    return (id: string) => map.get(id) ?? id;
  }, [products]);

  const locationName = useMemo(() => {
    const map = new Map(locations.map((l) => [l.id, l.name_en]));
    return (id: string) => map.get(id) ?? id;
  }, [locations]);

  if (!canCount) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleStart() {
    setError(null);
    setMessage(null);
    setStarting(true);
    const { error: rpcError } = await supabase.rpc("start_stocktake", {
      p_location_id: locationId,
    });
    setStarting(false);
    if (rpcError) {
      console.error("Start stocktake failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  function buildPayload() {
    return lines
      .filter((l): l is StocktakeLine & { product_id: string } =>
        Boolean(l.product_id)
      )
      .map((l) => {
        const raw = counts[l.product_id];
        const counted =
          raw === undefined || raw === "" ? null : Number(raw);
        return { product_id: l.product_id, counted_qty: counted };
      });
  }

  async function handleSaveProgress() {
    if (!activeStocktake) return;
    setError(null);
    setMessage(null);
    setSaving(true);
    const { error: rpcError } = await supabase.rpc("save_stocktake_counts", {
      p_stocktake_id: activeStocktake.id,
      p_lines: buildPayload(),
    });
    setSaving(false);
    if (rpcError) {
      console.error("Save counts failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setMessage(t.progressSaved);
    setRefreshKey((k) => k + 1);
  }

  async function handleSubmit() {
    if (!activeStocktake) return;
    setError(null);
    setMessage(null);
    setSubmitting(true);
    const { error: rpcError } = await supabase.rpc("submit_stocktake", {
      p_stocktake_id: activeStocktake.id,
    });
    setSubmitting(false);
    if (rpcError) {
      console.error("Submit stocktake failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setMessage(t.countSubmitted);
    setRefreshKey((k) => k + 1);
  }

  async function handleApprove(stocktakeId: string) {
    setApprovingId(stocktakeId);
    setError(null);
    setMessage(null);
    const { error: rpcError } = await supabase.rpc("approve_stocktake", {
      p_stocktake_id: stocktakeId,
    });
    setApprovingId(null);
    if (rpcError) {
      console.error("Approve stocktake failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setMessage(t.stocktakeApproved);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.stocktakeTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      {locationId && !activeStocktake && (
        <button
          type="button"
          disabled={starting}
          onClick={handleStart}
          className="bg-fluffy-orange h-11 max-w-md rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {starting ? t.startingStocktake : t.startStocktake}
        </button>
      )}

      {activeStocktake && (
        <section className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">
            {t.countSheetTitle} — {t.activeStocktakeInProgress}
          </h2>
          <div className="max-w-md overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.product}</th>
                  <th className="p-2 text-end">{t.countedQtyLabel}</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line) =>
                  line.product_id ? (
                    <tr
                      key={line.id}
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="p-2">{productName(line.product_id)}</td>
                      <td className="p-2 text-end">
                        <input
                          type="number"
                          inputMode="decimal"
                          min="0"
                          step="any"
                          value={
                            line.product_id in counts
                              ? counts[line.product_id]
                              : ""
                          }
                          onChange={(e) =>
                            setCounts((prev) => ({
                              ...prev,
                              [line.product_id as string]: e.target.value,
                            }))
                          }
                          className="h-9 w-24 rounded-md border border-zinc-300 px-2 text-end dark:border-zinc-700 dark:bg-zinc-900"
                        />
                      </td>
                    </tr>
                  ) : null
                )}
              </tbody>
            </table>
          </div>
          <div className="flex max-w-md gap-2">
            <button
              type="button"
              disabled={saving}
              onClick={handleSaveProgress}
              className="h-11 flex-1 rounded-md border border-zinc-300 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
            >
              {saving ? t.savingProgress : t.saveProgress}
            </button>
            <button
              type="button"
              disabled={submitting}
              onClick={handleSubmit}
              className="bg-fluffy-orange h-11 flex-1 rounded-md text-sm font-medium text-white disabled:opacity-60"
            >
              {submitting ? t.submittingCount : t.submitCount}
            </button>
          </div>
        </section>
      )}

      {isAdmin && (
        <section className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">{t.pendingApprovalTitle}</h2>
          {pendingApprovals.length === 0 ? (
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              {t.noPendingApprovals}
            </p>
          ) : (
            <div className="flex flex-col gap-4">
              {pendingApprovals.map((st) => (
                <div
                  key={st.id}
                  className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800"
                >
                  <div className="mb-2 flex items-center justify-between">
                    <span className="text-sm font-medium">
                      {locationName(st.location_id)}
                    </span>
                    <button
                      type="button"
                      disabled={approvingId === st.id}
                      onClick={() => handleApprove(st.id)}
                      className="bg-fluffy-orange h-9 rounded-md px-3 text-xs font-medium text-white disabled:opacity-60"
                    >
                      {approvingId === st.id
                        ? t.approvingStocktake
                        : t.approveStocktake}
                    </button>
                  </div>
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-max text-sm">
                      <thead className="bg-zinc-50 dark:bg-zinc-900">
                        <tr>
                          <th className="p-2 text-start">{t.product}</th>
                          <th className="p-2 text-end">
                            {t.systemQtyColumn}
                          </th>
                          <th className="p-2 text-end">
                            {t.countedQtyColumn}
                          </th>
                          <th className="p-2 text-end">{t.varianceColumn}</th>
                          <th className="p-2 text-end">
                            {t.varianceValueColumn}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {st.lines
                          .filter((l) => l.variance !== null && l.variance !== 0)
                          .map((l) => (
                            <tr
                              key={l.id}
                              className="border-t border-zinc-100 dark:border-zinc-800"
                            >
                              <td className="p-2">
                                {l.product_id ? productName(l.product_id) : ""}
                              </td>
                              <td className="p-2 text-end">{l.system_qty}</td>
                              <td className="p-2 text-end">
                                {l.counted_qty}
                              </td>
                              <td className="p-2 text-end">{l.variance}</td>
                              <td className="p-2 text-end">
                                {((l.variance ?? 0) * (l.unit_cost ?? 0)).toFixed(
                                  3
                                )}
                              </td>
                            </tr>
                          ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      {isAdmin && (
        <section>
          <h2 className="mb-2 text-lg font-semibold">
            {t.allStocktakesTitle}
          </h2>
          <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.location}</th>
                  <th className="p-2 text-start">{t.dateColumn}</th>
                  <th className="p-2 text-start">{t.statusColumn}</th>
                  <th className="p-2 text-end">{t.totalVarianceValue}</th>
                </tr>
              </thead>
              <tbody>
                {summary.map((s) => (
                  <tr
                    key={s.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">
                      {s.location_id ? locationName(s.location_id) : ""}
                    </td>
                    <td className="p-2">
                      {s.started_at
                        ? new Date(s.started_at).toLocaleDateString()
                        : ""}
                    </td>
                    <td className="p-2">{s.status}</td>
                    <td className="p-2 text-end">
                      {s.total_variance_value !== null
                        ? s.total_variance_value.toFixed(3)
                        : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}
    </div>
  );
}

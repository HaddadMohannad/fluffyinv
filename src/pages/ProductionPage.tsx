import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type Batch = Tables<"production_batches">;

export function ProductionPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations, locationId: headerLocationId } = useActiveLocation();

  const canWrite = profile?.role === "admin" || profile?.role === "warehouse_staff";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [locationId, setLocationId] = useState("");

  const [inputQuery, setInputQuery] = useState("");
  const [inputProductId, setInputProductId] = useState("");
  const [inputQty, setInputQty] = useState("");

  const [outputQuery, setOutputQuery] = useState("");
  const [outputProductId, setOutputProductId] = useState("");
  const [outputQty, setOutputQty] = useState("");
  const [totalCost, setTotalCost] = useState("");

  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [batches, setBatches] = useState<Batch[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);

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

  // Pre-fill with the header's active location for convenience -- still
  // freely changeable, since production isn't restricted to one location
  // for warehouse_staff (matches create_transfer's unrestricted scope).
  useEffect(() => {
    if (!locationId && headerLocationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- one-time default fill from the header's active location
      setLocationId(headerLocationId);
    }
  }, [headerLocationId, locationId]);

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

  function filteredProducts(query: string) {
    const q = query.trim().toLowerCase();
    if (!q) return products.slice(0, 20);
    return products
      .filter(
        (p) => p.name_en.toLowerCase().includes(q) || p.name_ar.includes(query)
      )
      .slice(0, 20);
  }

  if (!canWrite) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!inputProductId || !outputProductId) {
      setError(t.selectProductFirst);
      return;
    }
    if (inputProductId === outputProductId) {
      setError(t.sameProductError);
      return;
    }

    const inputQtyNum = Number(inputQty);
    const outputQtyNum = Number(outputQty);
    const costNum = Number(totalCost);
    if (
      !Number.isFinite(inputQtyNum) ||
      inputQtyNum <= 0 ||
      !Number.isFinite(outputQtyNum) ||
      outputQtyNum <= 0 ||
      !Number.isFinite(costNum) ||
      costNum < 0
    ) {
      setError(t.invalidQuantityOrCost);
      return;
    }

    setSaving(true);
    const { data, error: rpcError } = await supabase.rpc(
      "record_production_batch",
      {
        p_location_id: locationId,
        p_input_product_id: inputProductId,
        p_input_qty: inputQtyNum,
        p_output_product_id: outputProductId,
        p_output_qty: outputQtyNum,
        p_total_cost: costNum,
      }
    );
    setSaving(false);

    if (rpcError) {
      console.error("Record production batch failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    const result = data?.[0];
    setMessage(
      result
        ? `${t.entrySaved} ${t.yieldLabel}: ${result.yield_pct.toFixed(2)}%, ${t.costPerUnitLabel}: ${result.cost_per_unit.toFixed(3)}`
        : t.entrySaved
    );
    setInputProductId("");
    setInputQuery("");
    setInputQty("");
    setOutputProductId("");
    setOutputQuery("");
    setOutputQty("");
    setTotalCost("");
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.productionTitle}
      </h1>

      <form onSubmit={handleSubmit} className="flex max-w-md flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.location}
          <select
            value={locationId}
            onChange={(e) => setLocationId(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.location}
            </option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {locale === "ar" ? l.name_ar : l.name_en}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.inputProductLabel}
          <input
            type="text"
            value={inputProductId ? productName(inputProductId) : inputQuery}
            onChange={(e) => {
              setInputProductId("");
              setInputQuery(e.target.value);
            }}
            placeholder={t.searchProduct}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
          {!inputProductId && inputQuery && (
            <ul className="max-h-48 overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {filteredProducts(inputQuery).map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => {
                      setInputProductId(p.id);
                      setInputQuery("");
                    }}
                    className="flex h-11 w-full items-center px-3 text-start text-sm hover:bg-zinc-100 dark:hover:bg-zinc-900"
                  >
                    {locale === "ar" ? p.name_ar : p.name_en}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.inputQtyLabel}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            value={inputQty}
            onChange={(e) => setInputQty(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.outputProductLabel}
          <input
            type="text"
            value={outputProductId ? productName(outputProductId) : outputQuery}
            onChange={(e) => {
              setOutputProductId("");
              setOutputQuery(e.target.value);
            }}
            placeholder={t.searchProduct}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
          {!outputProductId && outputQuery && (
            <ul className="max-h-48 overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {filteredProducts(outputQuery).map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => {
                      setOutputProductId(p.id);
                      setOutputQuery("");
                    }}
                    className="flex h-11 w-full items-center px-3 text-start text-sm hover:bg-zinc-100 dark:hover:bg-zinc-900"
                  >
                    {locale === "ar" ? p.name_ar : p.name_en}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.outputQtyLabel}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            value={outputQty}
            onChange={(e) => setOutputQty(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.totalCostLabel}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            value={totalCost}
            onChange={(e) => setTotalCost(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}

        <button
          type="submit"
          disabled={
            saving ||
            !locationId ||
            !inputProductId ||
            !outputProductId ||
            !inputQty ||
            !outputQty ||
            !totalCost
          }
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.submitEntry}
        </button>
      </form>

      {locationId && (
        <section>
          <h2 className="mb-2 text-lg font-semibold">{t.recentBatchesTitle}</h2>
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
                      {productName(batch.output_product_id)} ({batch.output_qty})
                    </td>
                    <td className="p-2 text-end">{batch.total_cost}</td>
                    <td className="p-2 text-end">
                      {(batch.total_cost / batch.output_qty).toFixed(3)}
                    </td>
                    <td className="p-2 text-end">
                      {batch.yield_pct !== null ? `${batch.yield_pct}%` : "—"}
                    </td>
                    <td className="p-2">
                      {new Date(batch.created_at).toLocaleDateString()}
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

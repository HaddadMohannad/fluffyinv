import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type LedgerEntry = Tables<"stock_ledger">;

export function OpeningStockPage() {
  const { profile } = useAuth();
  const { t } = useLocale();

  const canWrite =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "warehouse_staff";

  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [selectedLocationId, setSelectedLocationId] = useState("");
  const [productQuery, setProductQuery] = useState("");
  const [productId, setProductId] = useState("");
  const [qty, setQty] = useState("");
  const [unitCost, setUnitCost] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [stock, setStock] = useState<{ product_id: string; qty: number }[]>([]);
  const [recent, setRecent] = useState<LedgerEntry[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);

  const isLocationLocked = profile?.role !== "admin";
  const locationId = isLocationLocked
    ? (profile?.location_id ?? "")
    : selectedLocationId;

  useEffect(() => {
    if (!canWrite) return;
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canWrite]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived lists when location is unset
      setStock([]);
      setRecent([]);
      return;
    }
    supabase
      .from("v_current_stock")
      .select("product_id, qty")
      .eq("location_id", locationId)
      .then(({ data }) => {
        setStock(
          (data ?? []).filter(
            (r): r is { product_id: string; qty: number } =>
              r.product_id !== null && r.qty !== null
          )
        );
      });
    supabase
      .from("stock_ledger")
      .select("*")
      .eq("location_id", locationId)
      .eq("movement", "opening")
      .order("created_at", { ascending: false })
      .limit(20)
      .then(({ data }) => setRecent(data ?? []));
  }, [locationId, refreshKey]);

  const productName = useMemo(() => {
    const map = new Map(products.map((p) => [p.id, p.name_en]));
    return (id: string) => map.get(id) ?? id;
  }, [products]);

  const filteredProducts = useMemo(() => {
    const q = productQuery.trim().toLowerCase();
    if (!q) return products.slice(0, 20);
    return products
      .filter(
        (p) =>
          p.name_en.toLowerCase().includes(q) ||
          p.name_ar.includes(productQuery)
      )
      .slice(0, 20);
  }, [products, productQuery]);

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

    if (!productId) {
      setError(t.selectProductFirst);
      return;
    }

    const qtyNum = Number(qty);
    const costNum = Number(unitCost);
    if (
      !Number.isFinite(qtyNum) ||
      qtyNum <= 0 ||
      !Number.isFinite(costNum) ||
      costNum < 0
    ) {
      setError(t.invalidQuantityOrCost);
      return;
    }

    setSaving(true);
    const { error: insertError } = await supabase.from("stock_ledger").insert({
      location_id: locationId,
      product_id: productId,
      qty: qtyNum,
      unit_cost: costNum,
      movement: "opening",
      note: note || null,
      created_by: profile?.id,
    });
    setSaving(false);

    if (insertError) {
      console.error("Opening stock insert failed:", insertError);
      setError(insertError.message);
      return;
    }

    setMessage(t.entrySaved);
    setProductId("");
    setProductQuery("");
    setQty("");
    setUnitCost("");
    setNote("");
    setRefreshKey((k) => k + 1);
  }

  async function handleReverse(entry: LedgerEntry) {
    const { error: reverseError } = await supabase.from("stock_ledger").insert({
      location_id: entry.location_id,
      product_id: entry.product_id,
      qty: -entry.qty,
      unit_cost: entry.unit_cost,
      movement: "opening",
      note: `Reversal of entry #${entry.id}`,
      created_by: profile?.id,
    });
    if (reverseError) {
      console.error("Reversal failed:", reverseError);
      setError(reverseError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.openingStockTitle}
      </h1>

      <form onSubmit={handleSubmit} className="flex max-w-md flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.location}
          <select
            value={locationId}
            onChange={(e) => setSelectedLocationId(e.target.value)}
            disabled={isLocationLocked}
            className="h-11 rounded-md border border-zinc-300 px-3 disabled:opacity-60 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.location}
            </option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {l.name_en}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.product}
          <input
            type="text"
            value={productId ? productName(productId) : productQuery}
            onChange={(e) => {
              setProductId("");
              setProductQuery(e.target.value);
            }}
            placeholder={t.searchProduct}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
          {!productId && productQuery && (
            <ul className="max-h-48 overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {filteredProducts.map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => {
                      setProductId(p.id);
                      setProductQuery("");
                    }}
                    className="flex h-11 w-full items-center px-3 text-start text-sm hover:bg-zinc-100 dark:hover:bg-zinc-900"
                  >
                    {p.name_en}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.quantity}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            value={qty}
            onChange={(e) => setQty(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.unitCost}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            value={unitCost}
            onChange={(e) => setUnitCost(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.note}
          <input
            type="text"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}

        <button
          type="submit"
          disabled={saving || !locationId || !productId}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.submitEntry}
        </button>
      </form>

      {locationId && (
        <>
          <section>
            <h2 className="mb-2 text-lg font-semibold">
              {t.currentStockTitle}
            </h2>
            <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              <table className="w-full min-w-max text-sm">
                <thead className="bg-zinc-50 dark:bg-zinc-900">
                  <tr>
                    <th className="p-2 text-start">{t.product}</th>
                    <th className="p-2 text-end">{t.quantity}</th>
                  </tr>
                </thead>
                <tbody>
                  {stock.map((s) => (
                    <tr
                      key={s.product_id}
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="p-2">{productName(s.product_id)}</td>
                      <td className="p-2 text-end">{s.qty}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section>
            <h2 className="mb-2 text-lg font-semibold">
              {t.recentEntriesTitle}
            </h2>
            <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              <table className="w-full min-w-max text-sm">
                <thead className="bg-zinc-50 dark:bg-zinc-900">
                  <tr>
                    <th className="p-2 text-start">{t.product}</th>
                    <th className="p-2 text-end">{t.quantity}</th>
                    <th className="p-2 text-end">{t.unitCost}</th>
                    <th className="p-2"></th>
                  </tr>
                </thead>
                <tbody>
                  {recent.map((entry) => (
                    <tr
                      key={entry.id}
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="p-2">{productName(entry.product_id)}</td>
                      <td className="p-2 text-end">{entry.qty}</td>
                      <td className="p-2 text-end">{entry.unit_cost}</td>
                      <td className="p-2 text-end">
                        <button
                          type="button"
                          onClick={() => handleReverse(entry)}
                          className="h-9 rounded-md border border-zinc-300 px-3 text-xs font-medium dark:border-zinc-700"
                        >
                          {t.reverse}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </div>
  );
}

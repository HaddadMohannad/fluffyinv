import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

export function WastePage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();

  const canWrite =
    profile?.role === "admin" || profile?.role === "branch_manager";
  const isLocationLocked = profile?.role !== "admin";

  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [selectedLocationId, setSelectedLocationId] = useState("");
  const [productQuery, setProductQuery] = useState("");
  const [productId, setProductId] = useState("");
  const [qty, setQty] = useState("");
  const [reasons, setReasons] = useState<Tables<"lookup_values">[]>([]);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [recent, setRecent] = useState<Tables<"waste_records">[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);

  const locationId = isLocationLocked
    ? (profile?.location_id ?? "")
    : selectedLocationId;

  const reasonLabel = useMemo(() => {
    const map = new Map(
      reasons.map((r) => [r.code, locale === "ar" ? r.name_ar : r.name_en])
    );
    return (code: string) => map.get(code) ?? code;
  }, [reasons, locale]);

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
    supabase
      .from("lookup_values")
      .select("*")
      .eq("list_key", "waste_reason")
      .eq("active", true)
      .order("sort_order")
      .then(({ data }) => {
        const rows = data ?? [];
        setReasons(rows);
        setReason((current) => current || (rows.length > 0 ? rows[0].code : ""));
      });
  }, [canWrite]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived list when location is unset
      setRecent([]);
      return;
    }
    supabase
      .from("waste_records")
      .select("*")
      .eq("location_id", locationId)
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
    if (!Number.isFinite(qtyNum) || qtyNum <= 0) {
      setError(t.invalidQuantity);
      return;
    }

    setSaving(true);
    const { data, error: rpcError } = await supabase.rpc("record_waste", {
      p_location_id: locationId,
      p_product_id: productId,
      p_qty: qtyNum,
      p_reason: reason,
    });
    setSaving(false);

    if (rpcError) {
      console.error("Record waste failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    const result = data?.[0];
    setMessage(
      result
        ? `${t.entrySaved} ${t.valueLostLabel}: ${result.value_lost.toFixed(3)}`
        : t.entrySaved
    );
    setProductId("");
    setProductQuery("");
    setQty("");
    setReason(reasons.length > 0 ? reasons[0].code : "");
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.wasteTitle}
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
          {t.wasteReasonLabel}
          <select
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            {reasons.map((r) => (
              <option key={r.code} value={r.code}>
                {reasonLabel(r.code)}
              </option>
            ))}
          </select>
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}

        <button
          type="submit"
          disabled={saving || !locationId || !productId || !reason}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.submitEntry}
        </button>
      </form>

      {locationId && (
        <section>
          <h2 className="mb-2 text-lg font-semibold">{t.recentEntriesTitle}</h2>
          <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.product}</th>
                  <th className="p-2 text-end">{t.quantity}</th>
                  <th className="p-2 text-start">{t.wasteReasonLabel}</th>
                  <th className="p-2 text-end">{t.valueLostLabel}</th>
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
                    <td className="p-2">{reasonLabel(entry.reason ?? "")}</td>
                    <td className="p-2 text-end">{entry.value_lost}</td>
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

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const CONFIRMATION_PREFIX = "CONFIRMATION_REQUIRED: ";

export function HospitalityPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations, locationId } = useActiveLocation();

  const canWrite =
    profile?.role === "admin" || profile?.role === "branch_manager";
  const isAdmin = profile?.role === "admin";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [productQuery, setProductQuery] = useState("");
  const [productId, setProductId] = useState("");
  const [qty, setQty] = useState("");
  const [hospitalityTypes, setHospitalityTypes] = useState<
    Tables<"lookup_values">[]
  >([]);
  const [hType, setHType] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pendingConfirmation, setPendingConfirmation] = useState<
    string | null
  >(null);

  const [monthUsage, setMonthUsage] = useState<number | null>(null);
  const [monthLimit, setMonthLimit] = useState<number | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const [limitLocationId, setLimitLocationId] = useState("");
  const [limitValue, setLimitValue] = useState("");
  const [savingLimit, setSavingLimit] = useState(false);
  const [limitMessage, setLimitMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!canWrite) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
    supabase
      .from("lookup_values")
      .select("*")
      .eq("list_key", "hospitality_type")
      .eq("active", true)
      .order("sort_order")
      .then(({ data }) => {
        const rows = data ?? [];
        setHospitalityTypes(rows);
        setHType((current) =>
          current || (rows.length > 0 ? rows[0].code : "")
        );
      });
  }, [canWrite]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when location is unset
      setMonthUsage(null);
      setMonthLimit(null);
      return;
    }
    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);
    const monthStr = monthStart.toISOString().slice(0, 10);

    supabase
      .from("hospitality_records")
      .select("value")
      .eq("location_id", locationId)
      .gte("created_at", monthStart.toISOString())
      .then(({ data }) => {
        const total = (data ?? []).reduce((sum, r) => sum + (r.value ?? 0), 0);
        setMonthUsage(total);
      });
    supabase
      .from("hospitality_limits")
      .select("limit_value")
      .eq("location_id", locationId)
      .eq("month", monthStr)
      .maybeSingle()
      .then(({ data }) => setMonthLimit(data?.limit_value ?? null));
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

  function resetForm() {
    setProductId("");
    setProductQuery("");
    setQty("");
    setHType(hospitalityTypes.length > 0 ? hospitalityTypes[0].code : "");
    setNote("");
  }

  async function submitEntry(confirmOverLimit: boolean) {
    const qtyNum = Number(qty);
    if (!Number.isFinite(qtyNum) || qtyNum <= 0) {
      setError(t.invalidQuantity);
      return;
    }

    setSaving(true);
    const { data, error: rpcError } = await supabase.rpc(
      "record_hospitality",
      {
        p_location_id: locationId,
        p_product_id: productId,
        p_qty: qtyNum,
        p_h_type: hType,
        p_note: note || undefined,
        p_confirm_over_limit: confirmOverLimit,
      }
    );
    setSaving(false);

    if (rpcError) {
      if (rpcError.message.startsWith(CONFIRMATION_PREFIX)) {
        setPendingConfirmation(
          rpcError.message.slice(CONFIRMATION_PREFIX.length)
        );
        return;
      }
      console.error("Record hospitality failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    setPendingConfirmation(null);
    const result = data?.[0];
    if (result && result.usage_pct !== null && result.usage_pct >= 80) {
      setMessage(
        `${t.entrySaved} ${t.warningAtPercentPrefix} ${result.usage_pct.toFixed(1)}${t.percentOfLimitSuffix}`
      );
    } else {
      setMessage(t.entrySaved);
    }
    resetForm();
    setRefreshKey((k) => k + 1);
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    setPendingConfirmation(null);

    if (!productId) {
      setError(t.selectProductFirst);
      return;
    }

    await submitEntry(false);
  }

  async function handleConfirmSubmit() {
    setError(null);
    setMessage(null);
    await submitEntry(true);
  }

  async function handleSaveLimit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLimitMessage(null);
    if (!limitLocationId) return;
    const value = Number(limitValue);
    if (!Number.isFinite(value) || value < 0) {
      setLimitMessage(t.invalidQuantity);
      return;
    }
    setSavingLimit(true);
    const monthStart = new Date();
    monthStart.setDate(1);
    const monthStr = monthStart.toISOString().slice(0, 10);
    const { error: upsertError } = await supabase
      .from("hospitality_limits")
      .upsert(
        { location_id: limitLocationId, month: monthStr, limit_value: value },
        { onConflict: "location_id,month" }
      );
    setSavingLimit(false);
    if (upsertError) {
      console.error("Save limit failed:", upsertError);
      setLimitMessage(upsertError.message);
      return;
    }
    setLimitMessage(t.limitSaved);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.hospitalityTitle}
      </h1>

      <form onSubmit={handleSubmit} className="flex max-w-md flex-col gap-4">
        {locationId && monthLimit !== null && monthUsage !== null && (
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.monthUsageLabel}: {monthUsage.toFixed(3)} / {monthLimit.toFixed(3)}{" "}
            JOD ({((monthUsage / monthLimit) * 100).toFixed(1)}%)
          </p>
        )}

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
          {t.hospitalityTypeLabel}
          <select
            value={hType}
            onChange={(e) => setHType(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            {hospitalityTypes.map((type) => (
              <option key={type.code} value={type.code}>
                {locale === "ar" ? type.name_ar : type.name_en}
              </option>
            ))}
          </select>
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

        {pendingConfirmation && (
          <div className="flex flex-col gap-2 rounded-md border border-amber-400 bg-amber-50 p-3 text-sm dark:border-amber-700 dark:bg-amber-950">
            <p>
              {t.requiresConfirmationPrefix} {pendingConfirmation}
            </p>
            <button
              type="button"
              disabled={saving}
              onClick={handleConfirmSubmit}
              className="h-9 rounded-md bg-amber-600 px-3 text-xs font-medium text-white disabled:opacity-60"
            >
              {t.confirmAndSubmit}
            </button>
          </div>
        )}

        <button
          type="submit"
          disabled={saving || !locationId || !productId || !hType}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.submitEntry}
        </button>
      </form>

      {isAdmin && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">
            {t.setMonthlyLimitTitle}
          </h2>
          <form onSubmit={handleSaveLimit} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.location}
              <select
                value={limitLocationId}
                onChange={(e) => setLimitLocationId(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
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
              {t.monthlyLimitValueLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={limitValue}
                onChange={(e) => setLimitValue(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            {limitMessage && (
              <p className="text-sm text-green-600">{limitMessage}</p>
            )}
            <button
              type="submit"
              disabled={savingLimit || !limitLocationId}
              className="h-11 rounded-md border border-zinc-300 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
            >
              {savingLimit ? t.savingLimit : t.saveLimit}
            </button>
          </form>
        </section>
      )}
    </div>
  );
}

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

const CONFIRMATION_PREFIX = "CONFIRMATION_REQUIRED: ";

export function AddHospitalityModal({
  locationId,
  onClose,
  onSaved,
}: {
  locationId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t, locale } = useLocale();

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

  useEffect(() => {
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
        setHType(rows.length > 0 ? rows[0].code : "");
      });
  }, []);

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
    setProductId("");
    setProductQuery("");
    setQty("");
    setHType(hospitalityTypes.length > 0 ? hospitalityTypes[0].code : "");
    setNote("");
    onSaved();
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

  return (
    <Modal title={t.addHospitalityAction} onClose={onClose}>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.product}
          <input
            type="text"
            autoFocus
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
          disabled={saving || !productId || !hType}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.submitEntry}
        </button>
      </form>
    </Modal>
  );
}

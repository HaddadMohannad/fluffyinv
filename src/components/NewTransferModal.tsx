import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

type DraftLine = { product_id: string; name: string; qty: string };

export function NewTransferModal({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t, locale } = useLocale();
  const { locations, locationId } = useActiveLocation();

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [fromLocationId, setFromLocationId] = useState(locationId);
  const [toLocationId, setToLocationId] = useState("");
  const [productQuery, setProductQuery] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .in("type", ["raw", "processed"])
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, []);

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

  function addLine(product: Tables<"products">) {
    setLines((prev) =>
      prev.some((l) => l.product_id === product.id)
        ? prev
        : [
            ...prev,
            {
              product_id: product.id,
              name: locale === "ar" ? product.name_ar : product.name_en,
              qty: "1",
            },
          ]
    );
    setProductQuery("");
  }

  function removeLine(productId: string) {
    setLines((prev) => prev.filter((l) => l.product_id !== productId));
  }

  function updateLineQty(productId: string, qty: string) {
    setLines((prev) =>
      prev.map((l) => (l.product_id === productId ? { ...l, qty } : l))
    );
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    if (!fromLocationId || !toLocationId) {
      setError(t.selectProductFirst);
      return;
    }
    if (fromLocationId === toLocationId) {
      setError(t.sameLocationError);
      return;
    }
    if (lines.length === 0) {
      setError(t.addLineFirst);
      return;
    }

    const parsedLines: { product_id: string; qty: number }[] = [];
    for (const line of lines) {
      const qtyNum = Number(line.qty);
      if (!Number.isFinite(qtyNum) || qtyNum <= 0) {
        setError(t.invalidQuantity);
        return;
      }
      parsedLines.push({ product_id: line.product_id, qty: qtyNum });
    }

    setSaving(true);
    const { error: rpcError } = await supabase.rpc("create_transfer", {
      p_from_location_id: fromLocationId,
      p_to_location_id: toLocationId,
      p_lines: parsedLines,
    });
    setSaving(false);

    if (rpcError) {
      console.error("Create transfer failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    onSaved();
    onClose();
  }

  return (
    <Modal title={t.createTransfer} onClose={onClose}>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.fromLocation}
          <select
            value={fromLocationId}
            onChange={(e) => setFromLocationId(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.fromLocation}
            </option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {locale === "ar" ? l.name_ar : l.name_en}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.toLocation}
          <select
            value={toLocationId}
            onChange={(e) => setToLocationId(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.toLocation}
            </option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {locale === "ar" ? l.name_ar : l.name_en}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.addProduct}
          <input
            type="text"
            value={productQuery}
            onChange={(e) => setProductQuery(e.target.value)}
            placeholder={t.searchProduct}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
          {productQuery && (
            <ul className="max-h-48 overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {filteredProducts.map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => addLine(p)}
                    className="flex h-11 w-full items-center px-3 text-start text-sm hover:bg-zinc-100 dark:hover:bg-zinc-900"
                  >
                    {locale === "ar" ? p.name_ar : p.name_en}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </label>

        {lines.length > 0 && (
          <div className="flex flex-col gap-2">
            <span className="text-sm font-medium">{t.productLines}</span>
            {lines.map((line) => (
              <div key={line.product_id} className="flex items-center gap-2">
                <span className="flex-1 text-sm">{line.name}</span>
                <input
                  type="number"
                  inputMode="decimal"
                  min="0"
                  step="any"
                  value={line.qty}
                  onChange={(e) => updateLineQty(line.product_id, e.target.value)}
                  className="h-11 w-24 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
                />
                <button
                  type="button"
                  onClick={() => removeLine(line.product_id)}
                  className="h-9 rounded-md border border-zinc-300 px-3 text-xs font-medium dark:border-zinc-700"
                >
                  {t.removeLine}
                </button>
              </div>
            ))}
          </div>
        )}

        {error && <p className="text-sm text-red-600">{error}</p>}

        <button
          type="submit"
          disabled={
            saving || !fromLocationId || !toLocationId || lines.length === 0
          }
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.creatingTransfer : t.createTransfer}
        </button>
      </form>
    </Modal>
  );
}

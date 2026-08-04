import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

export function TransferStockModal({
  locationId,
  onClose,
  onSaved,
}: {
  locationId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t, locale } = useLocale();
  const { locations } = useActiveLocation();

  const otherLocations = locations.filter((l) => l.id !== locationId);

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [productQuery, setProductQuery] = useState("");
  const [productId, setProductId] = useState("");
  const [toLocationId, setToLocationId] = useState("");
  const [qty, setQty] = useState("");
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

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    if (!productId) {
      setError(t.selectProductFirst);
      return;
    }
    if (!toLocationId) {
      setError(t.selectProductFirst);
      return;
    }

    const qtyNum = Number(qty);
    if (!Number.isFinite(qtyNum) || qtyNum <= 0) {
      setError(t.invalidQuantity);
      return;
    }

    setSaving(true);
    const { error: rpcError } = await supabase.rpc("create_transfer", {
      p_from_location_id: locationId,
      p_to_location_id: toLocationId,
      p_lines: [{ product_id: productId, qty: qtyNum }],
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
    <Modal title={t.transferStockAction} onClose={onClose}>
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
          {t.toLocation}
          <select
            value={toLocationId}
            onChange={(e) => setToLocationId(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.toLocation}
            </option>
            {otherLocations.map((l) => (
              <option key={l.id} value={l.id}>
                {locale === "ar" ? l.name_ar : l.name_en}
              </option>
            ))}
          </select>
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

        {error && <p className="text-sm text-red-600">{error}</p>}

        <button
          type="submit"
          disabled={saving || !productId || !toLocationId}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.creatingTransfer : t.createTransfer}
        </button>
      </form>
    </Modal>
  );
}

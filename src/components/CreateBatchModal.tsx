import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

export function CreateBatchModal({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t, locale } = useLocale();
  const { locations, locationId: headerLocationId } = useActiveLocation();

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [locationId, setLocationId] = useState(headerLocationId);

  const [inputQuery, setInputQuery] = useState("");
  const [inputProductId, setInputProductId] = useState("");
  const [inputQty, setInputQty] = useState("");

  const [outputQuery, setOutputQuery] = useState("");
  const [outputProductId, setOutputProductId] = useState("");
  const [outputQty, setOutputQty] = useState("");
  const [totalCost, setTotalCost] = useState("");

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

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

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
    const { error: rpcError } = await supabase.rpc(
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

    onSaved();
    onClose();
  }

  return (
    <Modal title={t.createBatchAction} onClose={onClose}>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
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
            autoFocus
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
    </Modal>
  );
}

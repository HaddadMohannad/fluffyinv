import { useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

export function TransferQuickModal({
  locationId,
  product,
  onClose,
  onSaved,
}: {
  locationId: string;
  product: Tables<"products">;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t, locale } = useLocale();
  const { locations } = useActiveLocation();

  const otherLocations = locations.filter((l) => l.id !== locationId);

  const [toLocationId, setToLocationId] = useState("");
  const [qty, setQty] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

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
      p_lines: [{ product_id: product.id, qty: qtyNum }],
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
    <Modal
      title={`${t.transferAction} — ${product.name_en}`}
      onClose={onClose}
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.toLocation}
          <select
            value={toLocationId}
            onChange={(e) => setToLocationId(e.target.value)}
            autoFocus
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
          disabled={saving || !toLocationId}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.creatingTransfer : t.createTransfer}
        </button>
      </form>
    </Modal>
  );
}

import { useEffect, useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

export function WasteQuickModal({
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

  const [reasons, setReasons] = useState<Tables<"lookup_values">[]>([]);
  const [reason, setReason] = useState("");
  const [qty, setQty] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    supabase
      .from("lookup_values")
      .select("*")
      .eq("list_key", "waste_reason")
      .eq("active", true)
      .order("sort_order")
      .then(({ data }) => {
        const rows = data ?? [];
        setReasons(rows);
        setReason(rows.length > 0 ? rows[0].code : "");
      });
  }, []);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    const qtyNum = Number(qty);
    if (!Number.isFinite(qtyNum) || qtyNum <= 0) {
      setError(t.invalidQuantity);
      return;
    }

    setSaving(true);
    const { error: rpcError } = await supabase.rpc("record_waste", {
      p_location_id: locationId,
      p_product_id: product.id,
      p_qty: qtyNum,
      p_reason: reason,
    });
    setSaving(false);

    if (rpcError) {
      console.error("Record waste failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    onSaved();
    onClose();
  }

  return (
    <Modal title={`${t.addWasteAction} — ${product.name_en}`} onClose={onClose}>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.quantity}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            autoFocus
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
                {locale === "ar" ? r.name_ar : r.name_en}
              </option>
            ))}
          </select>
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}

        <button
          type="submit"
          disabled={saving || !reason}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.submitEntry}
        </button>
      </form>
    </Modal>
  );
}

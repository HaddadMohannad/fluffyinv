import { useEffect, useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

const CONFIRMATION_PREFIX = "CONFIRMATION_REQUIRED: ";

export function HospitalityQuickModal({
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

  const [types, setTypes] = useState<Tables<"lookup_values">[]>([]);
  const [hType, setHType] = useState("");
  const [qty, setQty] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pendingConfirmation, setPendingConfirmation] = useState<
    string | null
  >(null);

  useEffect(() => {
    supabase
      .from("lookup_values")
      .select("*")
      .eq("list_key", "hospitality_type")
      .eq("active", true)
      .order("sort_order")
      .then(({ data }) => {
        const rows = data ?? [];
        setTypes(rows);
        setHType(rows.length > 0 ? rows[0].code : "");
      });
  }, []);

  async function submit(qtyNum: number, confirmOverLimit: boolean) {
    setSaving(true);
    const { error: rpcError } = await supabase.rpc("record_hospitality", {
      p_location_id: locationId,
      p_product_id: product.id,
      p_qty: qtyNum,
      p_h_type: hType,
      p_confirm_over_limit: confirmOverLimit,
    });
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

    onSaved();
    onClose();
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setPendingConfirmation(null);

    const qtyNum = Number(qty);
    if (!Number.isFinite(qtyNum) || qtyNum <= 0) {
      setError(t.invalidQuantity);
      return;
    }

    await submit(qtyNum, false);
  }

  async function handleConfirmSubmit() {
    setError(null);
    await submit(Number(qty), true);
  }

  return (
    <Modal
      title={`${t.addHospitalityAction} — ${product.name_en}`}
      onClose={onClose}
    >
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
          {t.hospitalityTypeLabel}
          <select
            value={hType}
            onChange={(e) => setHType(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            {types.map((type) => (
              <option key={type.code} value={type.code}>
                {locale === "ar" ? type.name_ar : type.name_en}
              </option>
            ))}
          </select>
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}

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
          disabled={saving || !hType}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.submitEntry}
        </button>
      </form>
    </Modal>
  );
}

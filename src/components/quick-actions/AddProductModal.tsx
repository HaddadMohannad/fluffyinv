import { useState, type FormEvent } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Modal } from "@/components/Modal";

type ProductType = Tables<"products">["type"];
type ProductUnit = Tables<"products">["unit"];

export function AddProductModal({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t } = useLocale();

  const [nameEn, setNameEn] = useState("");
  const [nameAr, setNameAr] = useState("");
  const [type, setType] = useState<ProductType>("raw");
  const [unit, setUnit] = useState<ProductUnit>("kg");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    if (!nameEn.trim() || !nameAr.trim()) {
      setError(t.selectProductFirst);
      return;
    }

    setSaving(true);
    const { error: insertError } = await supabase.from("products").insert({
      name_en: nameEn.trim(),
      name_ar: nameAr.trim(),
      type,
      unit,
    });
    setSaving(false);

    if (insertError) {
      console.error("Add product failed:", insertError);
      setError(insertError.message);
      return;
    }

    onSaved();
    onClose();
  }

  return (
    <Modal title={t.newProductTitle} onClose={onClose}>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.productNameEnLabel}
          <input
            type="text"
            autoFocus
            value={nameEn}
            onChange={(e) => setNameEn(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.productNameArLabel}
          <input
            type="text"
            dir="rtl"
            value={nameAr}
            onChange={(e) => setNameAr(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.productTypeLabel}
          <select
            value={type}
            onChange={(e) => setType(e.target.value as ProductType)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="raw">{t.categoryRaw}</option>
            <option value="processed">{t.categoryProcessed}</option>
            <option value="sellable">{t.categorySellable}</option>
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.productUnitLabel}
          <select
            value={unit}
            onChange={(e) => setUnit(e.target.value as ProductUnit)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="kg">kg</option>
            <option value="pcs">pcs</option>
          </select>
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}

        <button
          type="submit"
          disabled={saving || !nameEn.trim() || !nameAr.trim()}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.submitting : t.saveProduct}
        </button>
      </form>
    </Modal>
  );
}

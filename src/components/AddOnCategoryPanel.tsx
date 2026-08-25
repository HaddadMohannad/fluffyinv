import { useEffect, useState } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const emptyOptionForm = { name_en: "", name_ar: "", selling_price: "" };

/** One offered add-on category's existing options, plus an inline
 * quick-create form -- so a new option (e.g. a new sauce) can be added
 * without leaving the menu item it's being added from. The option is a
 * `products` row (is_addon=true) shared across every menu item that
 * offers this category, not scoped to the item you added it from. */
export function AddOnCategoryPanel({ categoryId }: { categoryId: string }) {
  const { t, locale } = useLocale();

  const [options, setOptions] = useState<Tables<"products">[]>([]);
  const [form, setForm] = useState(emptyOptionForm);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    supabase
      .from("addon_category_options")
      .select("product:product_id(*)")
      .eq("addon_category_id", categoryId)
      .then(({ data }) => {
        setOptions(
          (data ?? [])
            .map((r) => r.product)
            .filter((p): p is Tables<"products"> => p !== null)
        );
      });
  }, [categoryId, refreshKey]);

  async function handleAddOption() {
    setError(null);
    if (!form.name_en.trim() || !form.name_ar.trim()) {
      setError(t.branchNameRequired);
      return;
    }

    setSaving(true);
    const { data: product, error: insertError } = await supabase
      .from("products")
      .insert({
        name_en: form.name_en.trim(),
        name_ar: form.name_ar.trim(),
        selling_price: form.selling_price ? Number(form.selling_price) : null,
        unit: "pcs",
        is_addon: true,
        type: "sellable",
      })
      .select("id")
      .single();

    if (insertError || !product) {
      console.error("Create add-on option failed:", insertError);
      setError(insertError?.message ?? t.importFailed);
      setSaving(false);
      return;
    }

    const { error: linkError } = await supabase
      .from("addon_category_options")
      .insert({ addon_category_id: categoryId, product_id: product.id });
    setSaving(false);

    if (linkError) {
      console.error("Link add-on option to category failed:", linkError);
      setError(linkError.message);
      return;
    }

    setForm(emptyOptionForm);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
      {error && <p className="text-sm text-red-600">{error}</p>}

      <div>
        <h3 className="text-sm font-semibold">
          {t.addonOptionsInCategoryTitle}
        </h3>
        {options.length === 0 ? (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">
            {t.noAddonOptionsYet}
          </p>
        ) : (
          <div className="mt-2 flex flex-wrap gap-2">
            {options.map((o) => (
              <span
                key={o.id}
                className="rounded-full border border-zinc-200 px-3 py-1 text-xs dark:border-zinc-700"
              >
                {locale === "ar" ? o.name_ar : o.name_en}
                {o.selling_price !== null ? ` · ${o.selling_price}` : ""}
              </span>
            ))}
          </div>
        )}
      </div>

      <div className="flex flex-wrap items-end gap-2 border-t border-zinc-100 pt-3 dark:border-zinc-800">
        <label className="flex flex-col gap-1 text-sm">
          {t.productNameEnLabel}
          <input
            type="text"
            value={form.name_en}
            onChange={(e) => setForm({ ...form, name_en: e.target.value })}
            className="h-9 w-36 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {t.productNameArLabel}
          <input
            type="text"
            dir="auto"
            value={form.name_ar}
            onChange={(e) => setForm({ ...form, name_ar: e.target.value })}
            className="h-9 w-36 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {t.sellingPriceLabel}
          <input
            type="number"
            inputMode="decimal"
            step="any"
            min="0"
            value={form.selling_price}
            onChange={(e) =>
              setForm({ ...form, selling_price: e.target.value })
            }
            className="h-9 w-24 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>
        <button
          type="button"
          onClick={handleAddOption}
          disabled={saving}
          className="bg-fluffy-orange h-9 rounded-md px-3 text-sm font-medium text-white disabled:opacity-60"
        >
          {saving ? t.savingValue : t.addNewAddonOption}
        </button>
      </div>
      <p className="text-xs text-zinc-500 dark:text-zinc-400">
        {t.newAddonOptionNote}
      </p>
    </div>
  );
}

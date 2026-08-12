import { useEffect, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Enums, Tables } from "@/lib/supabase/database.types";
import { LocationAvailabilityPicker } from "@/components/LocationAvailabilityPicker";
import { RecipeLinesEditor } from "@/components/RecipeLinesEditor";

const emptyForm = {
  id: "",
  name_en: "",
  name_ar: "",
  sku: "",
  selling_price: "",
  unit: "pcs" as Enums<"product_unit">,
  active: true,
};

export function AddOnsPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();

  const canManage = profile?.role === "admin";

  const [addons, setAddons] = useState<Tables<"products">[]>([]);
  const [categories, setCategories] = useState<Tables<"addon_categories">[]>(
    []
  );
  const [assignedCategories, setAssignedCategories] = useState<Set<string>>(
    new Set()
  );
  const [form, setForm] = useState(emptyForm);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canManage) return;
    supabase
      .from("products")
      .select("*")
      .eq("is_addon", true)
      .order("name_en")
      .then(({ data }) => setAddons(data ?? []));
    supabase
      .from("addon_categories")
      .select("*")
      .eq("active", true)
      .order("sort_order")
      .then(({ data }) => setCategories(data ?? []));
  }, [canManage, refreshKey]);

  useEffect(() => {
    if (!form.id) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when there's no product selected yet
      setAssignedCategories(new Set());
      return;
    }
    supabase
      .from("addon_category_options")
      .select("addon_category_id")
      .eq("product_id", form.id)
      .then(({ data }) => {
        setAssignedCategories(
          new Set((data ?? []).map((r) => r.addon_category_id))
        );
      });
  }, [form.id, refreshKey]);

  if (!canManage) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function startNew() {
    setForm(emptyForm);
  }

  function startEdit(product: Tables<"products">) {
    setForm({
      id: product.id,
      name_en: product.name_en,
      name_ar: product.name_ar,
      sku: product.sku ?? "",
      selling_price:
        product.selling_price !== null ? String(product.selling_price) : "",
      unit: product.unit,
      active: product.active,
    });
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!form.name_en.trim() || !form.name_ar.trim()) {
      setError(t.branchNameRequired);
      return;
    }

    const payload = {
      name_en: form.name_en.trim(),
      name_ar: form.name_ar.trim(),
      sku: form.sku.trim() || null,
      selling_price: form.selling_price ? Number(form.selling_price) : null,
      unit: form.unit,
      active: form.active,
      is_addon: true,
      type: "sellable" as Enums<"product_type">,
    };

    setSaving(true);
    const { error: saveError } = form.id
      ? await supabase.from("products").update(payload).eq("id", form.id)
      : await supabase.from("products").insert(payload);
    setSaving(false);

    if (saveError) {
      console.error("Save add-on failed:", saveError);
      setError(saveError.message);
      return;
    }

    setMessage(t.valueSaved);
    setRefreshKey((k) => k + 1);
    if (!form.id) setForm(emptyForm);
  }

  async function toggleCategory(categoryId: string, assigned: boolean) {
    if (!form.id) return;
    setError(null);
    const { error: toggleError } = assigned
      ? await supabase
          .from("addon_category_options")
          .delete()
          .eq("product_id", form.id)
          .eq("addon_category_id", categoryId)
      : await supabase
          .from("addon_category_options")
          .insert({ product_id: form.id, addon_category_id: categoryId });
    if (toggleError) {
      console.error("Toggle add-on category failed:", toggleError);
      setError(toggleError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.addonsTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="w-full min-w-max text-sm">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <th className="p-2 text-start">{t.productNameEnLabel}</th>
              <th className="p-2 text-end">{t.sellingPriceLabel}</th>
              <th className="p-2 text-center">{t.activeLabel}</th>
              <th className="p-2" />
            </tr>
          </thead>
          <tbody>
            {addons.length === 0 && (
              <tr>
                <td className="p-2 text-zinc-500" colSpan={4}>
                  {t.noAddonsYet}
                </td>
              </tr>
            )}
            {addons.map((addon) => (
              <tr
                key={addon.id}
                className={`border-t border-zinc-100 dark:border-zinc-800 ${
                  addon.id === form.id ? "bg-fluffy-orange/10" : ""
                }`}
              >
                <td className="p-2">
                  {locale === "ar" ? addon.name_ar : addon.name_en}
                </td>
                <td className="p-2 text-end">{addon.selling_price ?? "—"}</td>
                <td className="p-2 text-center">{addon.active ? "✓" : ""}</td>
                <td className="p-2 text-end">
                  <button
                    type="button"
                    onClick={() => startEdit(addon)}
                    className="text-fluffy-orange text-sm font-medium"
                  >
                    {t.editValue}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <form onSubmit={handleSubmit} className="flex max-w-md flex-col gap-4">
        <h2 className="text-base font-semibold">
          {form.id ? t.editValue : t.newAddonTitle}
        </h2>

        <label className="flex flex-col gap-1 text-sm">
          {t.productNameEnLabel}
          <input
            type="text"
            value={form.name_en}
            onChange={(e) => setForm({ ...form, name_en: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.productNameArLabel}
          <input
            type="text"
            dir="auto"
            value={form.name_ar}
            onChange={(e) => setForm({ ...form, name_ar: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.skuLabel}
          <input
            type="text"
            value={form.sku}
            onChange={(e) => setForm({ ...form, sku: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
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
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.active}
            onChange={(e) => setForm({ ...form, active: e.target.checked })}
          />
          {t.activeLabel}
        </label>

        <div className="flex gap-2">
          <button
            type="submit"
            disabled={saving}
            className="bg-fluffy-orange h-11 rounded-md px-4 text-base font-medium text-white disabled:opacity-60"
          >
            {saving ? t.savingValue : t.addValue}
          </button>
          {form.id && (
            <button
              type="button"
              onClick={startNew}
              className="h-11 rounded-md border border-zinc-300 px-4 text-base font-medium dark:border-zinc-700"
            >
              {t.cancelEdit}
            </button>
          )}
        </div>
      </form>

      {form.id && (
        <>
          <section className="flex max-w-2xl flex-col gap-2">
            <h2 className="text-base font-semibold">
              {t.addonCategoriesAssignedTitle}
            </h2>
            <div className="flex flex-wrap gap-3">
              {categories.map((c) => (
                <label key={c.id} className="flex items-center gap-1.5 text-sm">
                  <input
                    type="checkbox"
                    checked={assignedCategories.has(c.id)}
                    onChange={() =>
                      toggleCategory(c.id, assignedCategories.has(c.id))
                    }
                  />
                  {locale === "ar" ? c.name_ar : c.name_en}
                </label>
              ))}
            </div>
          </section>

          <section className="flex max-w-2xl flex-col gap-2">
            <h2 className="text-base font-semibold">
              {t.branchAvailabilityTitle}
            </h2>
            <LocationAvailabilityPicker productId={form.id} />
          </section>

          <section className="flex max-w-2xl flex-col gap-2">
            <h2 className="text-base font-semibold">{t.recipeTitle}</h2>
            <RecipeLinesEditor parentProductId={form.id} />
          </section>
        </>
      )}
    </div>
  );
}

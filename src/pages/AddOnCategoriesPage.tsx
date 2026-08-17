import { useEffect, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const emptyForm = {
  id: "",
  name_en: "",
  name_ar: "",
  sort_order: "0",
  active: true,
};

export function AddOnCategoriesPage() {
  const { profile } = useAuth();
  const { t } = useLocale();

  const canManage = profile?.role === "admin";

  const [categories, setCategories] = useState<Tables<"addon_categories">[]>(
    []
  );
  const [form, setForm] = useState(emptyForm);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canManage) return;
    supabase
      .from("addon_categories")
      .select("*")
      .order("sort_order")
      .then(({ data }) => setCategories(data ?? []));
  }, [canManage, refreshKey]);

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

  function startEdit(category: Tables<"addon_categories">) {
    setForm({
      id: category.id,
      name_en: category.name_en,
      name_ar: category.name_ar,
      sort_order: String(category.sort_order),
      active: category.active,
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
      sort_order: Number(form.sort_order) || 0,
      active: form.active,
    };

    setSaving(true);
    const { error: saveError } = form.id
      ? await supabase
          .from("addon_categories")
          .update(payload)
          .eq("id", form.id)
      : await supabase.from("addon_categories").insert(payload);
    setSaving(false);

    if (saveError) {
      console.error("Save add-on category failed:", saveError);
      setError(saveError.message);
      return;
    }

    setMessage(t.valueSaved);
    setForm(emptyForm);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.addonCategoriesTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="w-full min-w-max text-sm">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <th className="p-2 text-start">{t.nameEnLabel}</th>
              <th className="p-2 text-start">{t.nameArLabel}</th>
              <th className="p-2 text-end">{t.sortOrderLabel}</th>
              <th className="p-2 text-center">{t.activeLabel}</th>
              <th className="p-2" />
            </tr>
          </thead>
          <tbody>
            {categories.length === 0 && (
              <tr>
                <td className="p-2 text-zinc-500" colSpan={5}>
                  {t.noAddonCategoriesYet}
                </td>
              </tr>
            )}
            {categories.map((category) => (
              <tr
                key={category.id}
                className="border-t border-zinc-100 dark:border-zinc-800"
              >
                <td className="p-2">{category.name_en}</td>
                <td className="p-2" dir="auto">
                  {category.name_ar}
                </td>
                <td className="p-2 text-end">{category.sort_order}</td>
                <td className="p-2 text-center">
                  {category.active ? "✓" : ""}
                </td>
                <td className="p-2 text-end">
                  <button
                    type="button"
                    onClick={() => startEdit(category)}
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
          {form.id ? t.editValue : t.newAddonCategoryTitle}
        </h2>

        <label className="flex flex-col gap-1 text-sm">
          {t.nameEnLabel}
          <input
            type="text"
            value={form.name_en}
            onChange={(e) => setForm({ ...form, name_en: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.nameArLabel}
          <input
            type="text"
            dir="auto"
            value={form.name_ar}
            onChange={(e) => setForm({ ...form, name_ar: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.sortOrderLabel}
          <input
            type="number"
            step="1"
            value={form.sort_order}
            onChange={(e) => setForm({ ...form, sort_order: e.target.value })}
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
    </div>
  );
}

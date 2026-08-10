import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const emptySectionForm = {
  id: "",
  name: "",
  sort_order: "0",
  active: true,
};

const emptyItemForm = {
  id: "",
  label: "",
  definition: "",
  sort_order: "0",
  active: true,
};

export function AuditCriteriaPage() {
  const { profile } = useAuth();
  const { t } = useLocale();

  const canManage = profile?.role === "admin";

  const [categories, setCategories] = useState<Tables<"audit_categories">[]>(
    []
  );
  const [categoryId, setCategoryId] = useState("");
  const [items, setItems] = useState<Tables<"audit_items">[]>([]);
  const [sectionForm, setSectionForm] = useState(emptySectionForm);
  const [itemForm, setItemForm] = useState(emptyItemForm);
  const [savingSection, setSavingSection] = useState(false);
  const [savingItem, setSavingItem] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canManage) return;
    supabase
      .from("audit_categories")
      .select("*")
      .order("sort_order")
      .then(({ data }) => {
        const rows = data ?? [];
        setCategories(rows);
        setCategoryId(
          (current) => current || (rows.length > 0 ? rows[0].id : "")
        );
      });
  }, [canManage, refreshKey]);

  useEffect(() => {
    if (!categoryId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived items when category is unset
      setItems([]);
      return;
    }
    supabase
      .from("audit_items")
      .select("*")
      .eq("category_id", categoryId)
      .order("sort_order")
      .then(({ data }) => setItems(data ?? []));
  }, [categoryId, refreshKey]);

  const categoryName = useMemo(() => {
    const map = new Map(categories.map((c) => [c.id, c.name]));
    return (id: string) => map.get(id) ?? id;
  }, [categories]);

  if (!canManage) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function startNewSection() {
    setSectionForm(emptySectionForm);
  }

  function startEditSection(category: Tables<"audit_categories">) {
    setSectionForm({
      id: category.id,
      name: category.name,
      sort_order: String(category.sort_order),
      active: category.active,
    });
  }

  function startNewItem() {
    setItemForm(emptyItemForm);
  }

  function startEditItem(item: Tables<"audit_items">) {
    setItemForm({
      id: item.id,
      label: item.label,
      definition: item.definition ?? "",
      sort_order: String(item.sort_order),
      active: item.active,
    });
  }

  async function handleSectionSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!sectionForm.name.trim()) {
      setError(t.sectionNameRequired);
      return;
    }

    const payload = {
      name: sectionForm.name.trim(),
      sort_order: Number(sectionForm.sort_order) || 0,
      active: sectionForm.active,
    };

    setSavingSection(true);
    const { error: saveError } = sectionForm.id
      ? await supabase
          .from("audit_categories")
          .update(payload)
          .eq("id", sectionForm.id)
      : await supabase.from("audit_categories").insert(payload);
    setSavingSection(false);

    if (saveError) {
      console.error("Save audit category failed:", saveError);
      setError(saveError.message);
      return;
    }

    setMessage(t.sectionSaved);
    setSectionForm(emptySectionForm);
    setRefreshKey((k) => k + 1);
  }

  async function handleItemSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!itemForm.label.trim()) {
      setError(t.itemLabelRequired);
      return;
    }

    const payload = {
      category_id: categoryId,
      label: itemForm.label.trim(),
      definition: itemForm.definition.trim() || null,
      sort_order: Number(itemForm.sort_order) || 0,
      active: itemForm.active,
    };

    setSavingItem(true);
    const { error: saveError } = itemForm.id
      ? await supabase.from("audit_items").update(payload).eq("id", itemForm.id)
      : await supabase.from("audit_items").insert(payload);
    setSavingItem(false);

    if (saveError) {
      console.error("Save audit item failed:", saveError);
      setError(saveError.message);
      return;
    }

    setMessage(t.itemSaved);
    setItemForm(emptyItemForm);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.auditCriteriaTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      {/* Sections */}
      <section className="flex flex-col gap-4">
        <h2 className="text-lg font-semibold">{t.auditSectionsLabel}</h2>

        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.sectionNameLabel}</th>
                <th className="p-2 text-end">{t.sortOrderLabel}</th>
                <th className="p-2 text-center">{t.activeLabel}</th>
                <th className="p-2" />
              </tr>
            </thead>
            <tbody>
              {categories.length === 0 && (
                <tr>
                  <td className="p-2 text-zinc-500" colSpan={4}>
                    {t.noSectionsYet}
                  </td>
                </tr>
              )}
              {categories.map((category) => (
                <tr
                  key={category.id}
                  className={`border-t border-zinc-100 dark:border-zinc-800 ${
                    category.id === categoryId ? "bg-fluffy-orange/10" : ""
                  }`}
                >
                  <td className="p-2">
                    <button
                      type="button"
                      onClick={() => setCategoryId(category.id)}
                      className="text-start font-medium"
                    >
                      {category.name}
                    </button>
                  </td>
                  <td className="p-2 text-end">{category.sort_order}</td>
                  <td className="p-2 text-center">
                    {category.active ? "✓" : ""}
                  </td>
                  <td className="p-2 text-end">
                    <button
                      type="button"
                      onClick={() => startEditSection(category)}
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

        <form
          onSubmit={handleSectionSubmit}
          className="flex max-w-md flex-col gap-4"
        >
          <h3 className="text-base font-semibold">
            {sectionForm.id ? t.editSectionTitle : t.newSectionTitle}
          </h3>

          <label className="flex flex-col gap-1 text-sm">
            {t.sectionNameLabel}
            <input
              type="text"
              dir="auto"
              value={sectionForm.name}
              onChange={(e) =>
                setSectionForm({ ...sectionForm, name: e.target.value })
              }
              className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>

          <label className="flex flex-col gap-1 text-sm">
            {t.sortOrderLabel}
            <input
              type="number"
              step="1"
              value={sectionForm.sort_order}
              onChange={(e) =>
                setSectionForm({ ...sectionForm, sort_order: e.target.value })
              }
              className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={sectionForm.active}
              onChange={(e) =>
                setSectionForm({ ...sectionForm, active: e.target.checked })
              }
            />
            {t.activeLabel}
          </label>

          <div className="flex gap-2">
            <button
              type="submit"
              disabled={savingSection}
              className="bg-fluffy-orange h-11 rounded-md px-4 text-base font-medium text-white disabled:opacity-60"
            >
              {savingSection ? t.savingValue : t.addSection}
            </button>
            {sectionForm.id && (
              <button
                type="button"
                onClick={startNewSection}
                className="h-11 rounded-md border border-zinc-300 px-4 text-base font-medium dark:border-zinc-700"
              >
                {t.cancelEdit}
              </button>
            )}
          </div>
        </form>
      </section>

      {/* Items within the selected section */}
      <section className="flex flex-col gap-4">
        <h2 className="text-lg font-semibold">
          {t.itemsInSection}
          {categoryId ? ` — ${categoryName(categoryId)}` : ""}
        </h2>

        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.itemLabelLabel}</th>
                <th className="p-2 text-start">{t.definitionLabel}</th>
                <th className="p-2 text-end">{t.sortOrderLabel}</th>
                <th className="p-2 text-center">{t.activeLabel}</th>
                <th className="p-2" />
              </tr>
            </thead>
            <tbody>
              {items.map((item) => (
                <tr
                  key={item.id}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="p-2 font-medium">{item.label}</td>
                  <td className="p-2 text-zinc-600 dark:text-zinc-400">
                    {item.definition}
                  </td>
                  <td className="p-2 text-end">{item.sort_order}</td>
                  <td className="p-2 text-center">{item.active ? "✓" : ""}</td>
                  <td className="p-2 text-end">
                    <button
                      type="button"
                      onClick={() => startEditItem(item)}
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

        <form
          onSubmit={handleItemSubmit}
          className="flex max-w-md flex-col gap-4"
        >
          <h3 className="text-base font-semibold">
            {itemForm.id ? t.editItemTitle : t.newItemTitle}
          </h3>

          <label className="flex flex-col gap-1 text-sm">
            {t.itemLabelLabel}
            <input
              type="text"
              dir="auto"
              value={itemForm.label}
              onChange={(e) =>
                setItemForm({ ...itemForm, label: e.target.value })
              }
              className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>

          <label className="flex flex-col gap-1 text-sm">
            {t.definitionLabel}
            <textarea
              dir="auto"
              value={itemForm.definition}
              onChange={(e) =>
                setItemForm({ ...itemForm, definition: e.target.value })
              }
              rows={3}
              className="rounded-md border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>

          <label className="flex flex-col gap-1 text-sm">
            {t.sortOrderLabel}
            <input
              type="number"
              step="1"
              value={itemForm.sort_order}
              onChange={(e) =>
                setItemForm({ ...itemForm, sort_order: e.target.value })
              }
              className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={itemForm.active}
              onChange={(e) =>
                setItemForm({ ...itemForm, active: e.target.checked })
              }
            />
            {t.activeLabel}
          </label>

          <div className="flex gap-2">
            <button
              type="submit"
              disabled={savingItem || !categoryId}
              className="bg-fluffy-orange h-11 rounded-md px-4 text-base font-medium text-white disabled:opacity-60"
            >
              {savingItem ? t.savingValue : t.addItem}
            </button>
            {itemForm.id && (
              <button
                type="button"
                onClick={startNewItem}
                className="h-11 rounded-md border border-zinc-300 px-4 text-base font-medium dark:border-zinc-700"
              >
                {t.cancelEdit}
              </button>
            )}
          </div>
        </form>
      </section>
    </div>
  );
}

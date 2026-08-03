import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const emptyForm = {
  id: "",
  code: "",
  name_en: "",
  name_ar: "",
  sort_order: "0",
  active: true,
};

export function LookupListsPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();

  const canManage = profile?.role === "admin";

  const [lists, setLists] = useState<Tables<"lookup_lists">[]>([]);
  const [listKey, setListKey] = useState("");
  const [values, setValues] = useState<Tables<"lookup_values">[]>([]);
  const [form, setForm] = useState(emptyForm);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canManage) return;
    supabase
      .from("lookup_lists")
      .select("*")
      .order("list_key")
      .then(({ data }) => {
        const rows = data ?? [];
        setLists(rows);
        setListKey((current) => current || (rows.length > 0 ? rows[0].list_key : ""));
      });
  }, [canManage]);

  useEffect(() => {
    if (!listKey) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived list when list_key is unset
      setValues([]);
      return;
    }
    supabase
      .from("lookup_values")
      .select("*")
      .eq("list_key", listKey)
      .order("sort_order")
      .then(({ data }) => setValues(data ?? []));
  }, [listKey, refreshKey]);

  const listName = useMemo(() => {
    const map = new Map(
      lists.map((l) => [l.list_key, locale === "ar" ? l.name_ar : l.name_en])
    );
    return (key: string) => map.get(key) ?? key;
  }, [lists, locale]);

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

  function startEdit(value: Tables<"lookup_values">) {
    setForm({
      id: value.id,
      code: value.code,
      name_en: value.name_en,
      name_ar: value.name_ar,
      sort_order: String(value.sort_order),
      active: value.active,
    });
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!form.code.trim() || !form.name_en.trim() || !form.name_ar.trim()) {
      setError(t.codeRequired);
      return;
    }

    const payload = {
      list_key: listKey,
      code: form.code.trim(),
      name_en: form.name_en.trim(),
      name_ar: form.name_ar.trim(),
      sort_order: Number(form.sort_order) || 0,
      active: form.active,
    };

    setSaving(true);
    const { error: saveError } = form.id
      ? await supabase.from("lookup_values").update(payload).eq("id", form.id)
      : await supabase.from("lookup_values").insert(payload);
    setSaving(false);

    if (saveError) {
      console.error("Save lookup value failed:", saveError);
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
        {t.lookupListsTitle}
      </h1>

      <label className="flex max-w-md flex-col gap-1 text-sm">
        {t.selectListLabel}
        <select
          value={listKey}
          onChange={(e) => {
            setListKey(e.target.value);
            startNew();
          }}
          className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
        >
          {lists.map((l) => (
            <option key={l.list_key} value={l.list_key}>
              {listName(l.list_key)}
            </option>
          ))}
        </select>
      </label>

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="w-full min-w-max text-sm">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <th className="p-2 text-start">{t.codeLabel}</th>
              <th className="p-2 text-start">{t.nameEnLabel}</th>
              <th className="p-2 text-start">{t.nameArLabel}</th>
              <th className="p-2 text-end">{t.sortOrderLabel}</th>
              <th className="p-2 text-center">{t.activeLabel}</th>
              <th className="p-2" />
            </tr>
          </thead>
          <tbody>
            {values.map((value) => (
              <tr
                key={value.id}
                className="border-t border-zinc-100 dark:border-zinc-800"
              >
                <td className="p-2">{value.code}</td>
                <td className="p-2">{value.name_en}</td>
                <td className="p-2">{value.name_ar}</td>
                <td className="p-2 text-end">{value.sort_order}</td>
                <td className="p-2 text-center">{value.active ? "✓" : ""}</td>
                <td className="p-2 text-end">
                  <button
                    type="button"
                    onClick={() => startEdit(value)}
                    className="text-sm font-medium text-fluffy-orange"
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
        <h2 className="text-lg font-semibold">
          {form.id ? t.editValue : t.newValueTitle}
        </h2>

        <label className="flex flex-col gap-1 text-sm">
          {t.codeLabel}
          <input
            type="text"
            value={form.code}
            onChange={(e) => setForm({ ...form, code: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

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
            dir="rtl"
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

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}

        <div className="flex gap-2">
          <button
            type="submit"
            disabled={saving || !listKey}
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

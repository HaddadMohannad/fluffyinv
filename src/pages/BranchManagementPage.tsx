import { useEffect, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Enums, Tables } from "@/lib/supabase/database.types";

type Location = Tables<"locations">;
type LocationTypeValue = Enums<"location_type">;

const emptyForm = {
  id: "",
  name_en: "",
  name_ar: "",
  type: "branch" as LocationTypeValue,
  city: "",
  active: true,
  open_time: "",
  close_time: "",
  day_close_cutoff_time: "",
};

export function BranchManagementPage() {
  const { profile } = useAuth();
  const { t } = useLocale();

  const canManage = profile?.role === "admin";

  const [locations, setLocations] = useState<Location[]>([]);
  const [form, setForm] = useState(emptyForm);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canManage) return;
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
  }, [canManage, refreshKey]);

  if (!canManage) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function startEdit(location: Location) {
    setForm({
      id: location.id,
      name_en: location.name_en,
      name_ar: location.name_ar,
      type: location.type,
      city: location.city ?? "",
      active: location.active,
      open_time: location.open_time ?? "",
      close_time: location.close_time ?? "",
      day_close_cutoff_time: location.day_close_cutoff_time ?? "",
    });
    setMessage(null);
    setError(null);
  }

  function startNew() {
    setForm(emptyForm);
    setMessage(null);
    setError(null);
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!form.name_en.trim() || !form.name_ar.trim()) {
      setError(t.branchNameRequired);
      return;
    }

    setSaving(true);
    const payload = {
      name_en: form.name_en.trim(),
      name_ar: form.name_ar.trim(),
      type: form.type,
      city: form.city.trim() || null,
      active: form.active,
      open_time: form.open_time || null,
      close_time: form.close_time || null,
      day_close_cutoff_time: form.day_close_cutoff_time || null,
    };

    const { error: saveError } = form.id
      ? await supabase.from("locations").update(payload).eq("id", form.id)
      : await supabase.from("locations").insert(payload);
    setSaving(false);

    if (saveError) {
      console.error("Save branch failed:", saveError);
      setError(saveError.message);
      return;
    }

    setMessage(t.branchSaved);
    setForm(emptyForm);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.branchesTitle}
      </h1>

      <form onSubmit={handleSubmit} className="flex max-w-md flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.nameEnLabel}
          <input
            type="text"
            value={form.name_en}
            onChange={(e) => setForm((f) => ({ ...f, name_en: e.target.value }))}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.nameArLabel}
          <input
            type="text"
            value={form.name_ar}
            onChange={(e) => setForm((f) => ({ ...f, name_ar: e.target.value }))}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.locationTypeLabel}
          <select
            value={form.type}
            onChange={(e) =>
              setForm((f) => ({
                ...f,
                type: e.target.value as LocationTypeValue,
              }))
            }
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="branch">{t.typeBranch}</option>
            <option value="warehouse">{t.typeWarehouse}</option>
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.cityLabel}
          <input
            type="text"
            value={form.city}
            onChange={(e) => setForm((f) => ({ ...f, city: e.target.value }))}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.active}
            onChange={(e) =>
              setForm((f) => ({ ...f, active: e.target.checked }))
            }
            className="h-5 w-5"
          />
          {t.activeLabel}
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.openTimeLabel}
          <input
            type="time"
            value={form.open_time}
            onChange={(e) =>
              setForm((f) => ({ ...f, open_time: e.target.value }))
            }
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.closeTimeLabel}
          <input
            type="time"
            value={form.close_time}
            onChange={(e) =>
              setForm((f) => ({ ...f, close_time: e.target.value }))
            }
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.dayCloseCutoffLabel}
          <input
            type="time"
            value={form.day_close_cutoff_time}
            onChange={(e) =>
              setForm((f) => ({ ...f, day_close_cutoff_time: e.target.value }))
            }
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}

        <div className="flex gap-2">
          <button
            type="submit"
            disabled={saving}
            className="bg-fluffy-orange h-11 flex-1 rounded-md text-base font-medium text-white disabled:opacity-60"
          >
            {saving ? t.savingBranch : t.saveBranch}
          </button>
          {form.id && (
            <button
              type="button"
              onClick={startNew}
              className="h-11 rounded-md border border-zinc-300 px-4 text-sm font-medium dark:border-zinc-700"
            >
              {t.cancelEdit}
            </button>
          )}
        </div>
      </form>

      <section>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="text-lg font-semibold">{t.branches}</h2>
          <button
            type="button"
            onClick={startNew}
            className="h-9 rounded-md border border-zinc-300 px-3 text-xs font-medium dark:border-zinc-700"
          >
            {t.newBranch}
          </button>
        </div>
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.nameEnLabel}</th>
                <th className="p-2 text-start">{t.locationTypeLabel}</th>
                <th className="p-2 text-start">{t.cityLabel}</th>
                <th className="p-2 text-start">{t.activeLabel}</th>
                <th className="p-2"></th>
              </tr>
            </thead>
            <tbody>
              {locations.map((l) => (
                <tr
                  key={l.id}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="p-2">{l.name_en}</td>
                  <td className="p-2">
                    {l.type === "warehouse" ? t.typeWarehouse : t.typeBranch}
                  </td>
                  <td className="p-2">{l.city ?? ""}</td>
                  <td className="p-2">{l.active ? t.activeLabel : ""}</td>
                  <td className="p-2 text-end">
                    <button
                      type="button"
                      onClick={() => startEdit(l)}
                      className="h-9 rounded-md border border-zinc-300 px-3 text-xs font-medium dark:border-zinc-700"
                    >
                      {t.editBranch}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useSearchParams } from "react-router";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useAuditLocations } from "@/lib/location/useAuditLocations";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Pill } from "@/components/Pill";
import type { PillTone } from "@/lib/pillColors";

type Status = "open" | "in_progress" | "closed";

const STATUS_TONE: Record<Status, PillTone> = {
  open: "red",
  in_progress: "amber",
  closed: "green",
};

const emptyForm = {
  id: "",
  description: "",
  action_required: "",
  owner: "",
  due_date: "",
  estimated_cost: "",
  status: "open" as Status,
  recheck_date: "",
  recheck_result: "",
};

export function CorrectiveActionsPage() {
  const { profile } = useAuth();
  const { t } = useLocale();
  const locations = useAuditLocations();
  const [searchParams] = useSearchParams();
  const visitIdFromLink = searchParams.get("visit_id");

  const canWrite =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "inspector";

  const [locationId, setLocationId] = useState("");
  const [actions, setActions] = useState<Tables<"corrective_actions">[]>([]);
  const [statusFilter, setStatusFilter] = useState<Status | "all">("all");
  const [filterToVisit, setFilterToVisit] = useState(Boolean(visitIdFromLink));
  const [form, setForm] = useState(emptyForm);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (locations.length === 0) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- recovering a stale/missing selection once the audit-locations list loads
    setLocationId((current) =>
      current && locations.some((l) => l.id === current)
        ? current
        : locations[0].id
    );
  }, [locations]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived list when location is unset
      setActions([]);
      return;
    }
    let query = supabase
      .from("corrective_actions")
      .select("*")
      .eq("location_id", locationId);
    if (filterToVisit && visitIdFromLink) {
      query = query.eq("visit_id", visitIdFromLink);
    }
    query
      .order("due_date", { ascending: true, nullsFirst: false })
      .then(({ data }) => setActions(data ?? []));
  }, [locationId, refreshKey, filterToVisit, visitIdFromLink]);

  const filteredActions = useMemo(() => {
    if (statusFilter === "all") return actions;
    return actions.filter((a) => a.status === statusFilter);
  }, [actions, statusFilter]);

  const today = new Date().toISOString().slice(0, 10);

  if (!canWrite) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function startNew() {
    setForm(emptyForm);
  }

  function startEdit(action: Tables<"corrective_actions">) {
    setForm({
      id: action.id,
      description: action.description,
      action_required: action.action_required ?? "",
      owner: action.owner ?? "",
      due_date: action.due_date ?? "",
      estimated_cost:
        action.estimated_cost === null ? "" : String(action.estimated_cost),
      status: action.status as Status,
      recheck_date: action.recheck_date ?? "",
      recheck_result: action.recheck_result ?? "",
    });
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!form.description.trim()) {
      setError(t.descriptionRequired);
      return;
    }
    if (form.status === "closed" && !form.recheck_result.trim()) {
      setError(t.recheckResultRequiredToClose);
      return;
    }
    if (!locationId) {
      setError(t.selectBranchFirst);
      return;
    }

    const payload = {
      location_id: locationId,
      visit_id: form.id ? undefined : visitIdFromLink,
      description: form.description.trim(),
      action_required: form.action_required.trim() || null,
      owner: form.owner.trim() || null,
      due_date: form.due_date || null,
      estimated_cost: form.estimated_cost ? Number(form.estimated_cost) : null,
      status: form.status,
      recheck_date: form.recheck_date || null,
      recheck_result: form.recheck_result.trim() || null,
      created_by: profile?.id,
    };

    setSaving(true);
    const { error: saveError } = form.id
      ? await supabase
          .from("corrective_actions")
          .update(payload)
          .eq("id", form.id)
      : await supabase.from("corrective_actions").insert(payload);
    setSaving(false);

    if (saveError) {
      console.error("Save corrective action failed:", saveError);
      setError(saveError.message);
      return;
    }

    setMessage(t.actionSaved);
    setForm(emptyForm);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.correctiveActionsTitle}
      </h1>

      <label className="flex max-w-xs flex-col gap-1 text-sm">
        {t.branchTypeLabel}
        <select
          value={locationId}
          onChange={(e) => setLocationId(e.target.value)}
          className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
        >
          {locations.map((loc) => (
            <option key={loc.id} value={loc.id}>
              {loc.name_ar || loc.name_en}
            </option>
          ))}
        </select>
      </label>

      <label className="flex max-w-xs flex-col gap-1 text-sm">
        {t.statusLabel}
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as Status | "all")}
          className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
        >
          <option value="all">{t.allStatuses}</option>
          <option value="open">{t.statusOpen}</option>
          <option value="in_progress">{t.statusInProgress}</option>
          <option value="closed">{t.statusClosed}</option>
        </select>
      </label>

      {filterToVisit && visitIdFromLink && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-zinc-200 bg-zinc-50 p-3 text-sm dark:border-zinc-800 dark:bg-zinc-900">
          <span>{t.showingActionsForVisit}</span>
          <button
            type="button"
            onClick={() => setFilterToVisit(false)}
            className="text-fluffy-orange font-medium"
          >
            {t.showAllActionsLink}
          </button>
        </div>
      )}

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="w-full min-w-max text-sm">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <th className="p-2 text-start">{t.descriptionLabel}</th>
              <th className="p-2 text-start">{t.ownerLabel}</th>
              <th className="p-2 text-start">{t.dueDateLabel}</th>
              <th className="p-2 text-end">{t.estimatedCostLabel}</th>
              <th className="p-2 text-center">{t.statusLabel}</th>
              <th className="p-2" />
            </tr>
          </thead>
          <tbody>
            {filteredActions.map((action) => {
              const overdue =
                action.due_date &&
                action.due_date < today &&
                action.status !== "closed";
              return (
                <tr
                  key={action.id}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="max-w-xs p-2">{action.description}</td>
                  <td className="p-2">{action.owner}</td>
                  <td
                    className={`p-2 ${overdue ? "font-semibold text-red-600" : ""}`}
                  >
                    {action.due_date}
                  </td>
                  <td className="p-2 text-end">
                    {action.estimated_cost !== null
                      ? `${action.estimated_cost} JOD`
                      : "—"}
                  </td>
                  <td className="p-2 text-center">
                    <Pill tone={STATUS_TONE[action.status as Status]}>
                      {action.status === "open"
                        ? t.statusOpen
                        : action.status === "in_progress"
                          ? t.statusInProgress
                          : t.statusClosed}
                    </Pill>
                  </td>
                  <td className="p-2 text-end">
                    <button
                      type="button"
                      onClick={() => startEdit(action)}
                      className="text-fluffy-orange text-sm font-medium"
                    >
                      {t.editValue}
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <form onSubmit={handleSubmit} className="flex max-w-md flex-col gap-4">
        <h2 className="text-lg font-semibold">
          {form.id ? t.editActionTitle : t.newActionTitle}
        </h2>

        <label className="flex flex-col gap-1 text-sm">
          {t.descriptionLabel}
          <textarea
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
            rows={2}
            className="rounded-md border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.actionRequiredLabel}
          <textarea
            value={form.action_required}
            onChange={(e) =>
              setForm({ ...form, action_required: e.target.value })
            }
            rows={2}
            className="rounded-md border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.ownerLabel}
          <input
            type="text"
            value={form.owner}
            onChange={(e) => setForm({ ...form, owner: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.dueDateLabel}
          <input
            type="date"
            value={form.due_date}
            onChange={(e) => setForm({ ...form, due_date: e.target.value })}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.estimatedCostLabel}
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            value={form.estimated_cost}
            onChange={(e) =>
              setForm({ ...form, estimated_cost: e.target.value })
            }
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.statusLabel}
          <select
            value={form.status}
            onChange={(e) =>
              setForm({ ...form, status: e.target.value as Status })
            }
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="open">{t.statusOpen}</option>
            <option value="in_progress">{t.statusInProgress}</option>
            <option value="closed">{t.statusClosed}</option>
          </select>
        </label>

        {form.status === "closed" && (
          <>
            <label className="flex flex-col gap-1 text-sm">
              {t.recheckDateLabel}
              <input
                type="date"
                value={form.recheck_date}
                onChange={(e) =>
                  setForm({ ...form, recheck_date: e.target.value })
                }
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.recheckResultLabel}
              <textarea
                value={form.recheck_result}
                onChange={(e) =>
                  setForm({ ...form, recheck_result: e.target.value })
                }
                rows={2}
                className="rounded-md border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
          </>
        )}

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}

        <div className="flex gap-2">
          <button
            type="submit"
            disabled={saving || !locationId}
            className="bg-fluffy-orange h-11 rounded-md px-4 text-base font-medium text-white disabled:opacity-60"
          >
            {saving ? t.savingValue : t.addAction}
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

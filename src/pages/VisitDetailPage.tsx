import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Pill } from "@/components/Pill";
import type { PillTone } from "@/lib/pillColors";

const ACTION_STATUS_TONE: Record<string, PillTone> = {
  open: "red",
  in_progress: "amber",
  closed: "green",
};

type VisitWithRelations = Tables<"audit_visits"> & {
  locations: Tables<"locations"> | null;
  profiles: Tables<"profiles"> | null;
};

type ItemScoreWithItem = Tables<"audit_item_scores"> & {
  audit_items:
    | (Tables<"audit_items"> & {
        audit_categories: Tables<"audit_categories"> | null;
      })
    | null;
};

type CategoryGroup = {
  categoryId: string;
  categoryName: string;
  sortOrder: number;
  rows: ItemScoreWithItem[];
};

type EditAnswer = { score: 0 | 1 | null; note: string };

function scoreTone(score: number | null): PillTone {
  if (score === 1) return "green";
  if (score === 0) return "red";
  return "zinc";
}

function classificationTone(classification: string | null): PillTone {
  if (classification === "ممتاز") return "green";
  if (classification === "يحتاج تحسين") return "amber";
  return "red";
}

export function VisitDetailPage() {
  const { id } = useParams();
  const { t, locale } = useLocale();
  const { profile } = useAuth();
  const navigate = useNavigate();
  const isAdmin = profile?.role === "admin";

  const [visit, setVisit] = useState<VisitWithRelations | null>(null);
  const [scoreSummary, setScoreSummary] =
    useState<Tables<"v_audit_visit_scores"> | null>(null);
  const [itemScores, setItemScores] = useState<ItemScoreWithItem[]>([]);
  const [actions, setActions] = useState<Tables<"corrective_actions">[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  const [editing, setEditing] = useState(false);
  const [editVisitDate, setEditVisitDate] = useState("");
  const [editNotes, setEditNotes] = useState("");
  const [editAnswers, setEditAnswers] = useState<Record<string, EditAnswer>>(
    {}
  );
  const [saving, setSaving] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadVisit = useCallback(() => {
    if (!id) return;

    supabase
      .from("audit_visits")
      .select("*, locations(*), profiles(*)")
      .eq("id", id)
      .maybeSingle()
      .then(({ data, error: fetchError }) => {
        if (fetchError || !data) {
          setNotFound(true);
          setLoading(false);
          return;
        }
        setVisit(data as VisitWithRelations);
        setLoading(false);
      });

    supabase
      .from("v_audit_visit_scores")
      .select("*")
      .eq("visit_id", id)
      .maybeSingle()
      .then(({ data }) => setScoreSummary(data));

    supabase
      .from("audit_item_scores")
      .select("*, audit_items(*, audit_categories(*))")
      .eq("visit_id", id)
      .then(({ data }) =>
        setItemScores((data as ItemScoreWithItem[] | null) ?? [])
      );

    supabase
      .from("corrective_actions")
      .select("*")
      .eq("visit_id", id)
      .order("due_date", { ascending: true, nullsFirst: false })
      .then(({ data }) => setActions(data ?? []));
  }, [id]);

  useEffect(() => {
    loadVisit();
  }, [loadVisit]);

  const categoryGroups = useMemo<CategoryGroup[]>(() => {
    const map = new Map<string, CategoryGroup>();
    for (const row of itemScores) {
      const cat = row.audit_items?.audit_categories;
      const catId = cat?.id ?? "uncategorized";
      if (!map.has(catId)) {
        map.set(catId, {
          categoryId: catId,
          categoryName: cat?.name ?? "",
          sortOrder: cat?.sort_order ?? 0,
          rows: [],
        });
      }
      map.get(catId)!.rows.push(row);
    }
    return Array.from(map.values()).sort((a, b) => a.sortOrder - b.sortOrder);
  }, [itemScores]);

  async function handleViewEvidence(path: string) {
    const { data, error: signError } = await supabase.storage
      .from("audit-evidence")
      .createSignedUrl(path, 60);
    if (signError || !data) {
      console.error("Sign evidence URL failed:", signError);
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  function startEdit() {
    if (!visit) return;
    setError(null);
    setEditVisitDate(visit.visit_date);
    setEditNotes(visit.notes ?? "");
    setEditAnswers(
      Object.fromEntries(
        itemScores.map((row) => [
          row.id,
          { score: row.score as 0 | 1 | null, note: row.note ?? "" },
        ])
      )
    );
    setEditing(true);
  }

  function setEditScore(rowId: string, score: 0 | 1 | null) {
    setEditAnswers((prev) => ({
      ...prev,
      [rowId]: { score, note: prev[rowId]?.note ?? "" },
    }));
  }

  function setEditNote(rowId: string, note: string) {
    setEditAnswers((prev) => ({
      ...prev,
      [rowId]: { score: prev[rowId]?.score ?? null, note },
    }));
  }

  async function handleSaveEdit() {
    if (!id) return;
    setError(null);
    setSaving(true);

    const p_scores = Object.entries(editAnswers).map(([rowId, a]) => ({
      id: rowId,
      score: a.score,
      note: a.note.trim() || null,
    }));

    const { error: rpcError } = await supabase.rpc("update_audit_visit", {
      p_visit_id: id,
      p_visit_date: editVisitDate,
      p_notes: editNotes.trim() || undefined,
      p_scores,
    });
    setSaving(false);

    if (rpcError) {
      console.error("Update audit visit failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    setEditing(false);
    loadVisit();
  }

  async function handleDelete() {
    if (!id) return;
    setError(null);
    setDeleting(true);
    const { error: rpcError } = await supabase.rpc("delete_audit_visit", {
      p_visit_id: id,
    });
    setDeleting(false);

    if (rpcError) {
      console.error("Delete audit visit failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    navigate("/quality-dashboard");
  }

  if (loading) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-sm text-zinc-500">
        {t.loadingSales}
      </div>
    );
  }

  if (notFound || !visit) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.visitNotFound}
      </div>
    );
  }

  const locationName = visit.locations
    ? locale === "ar"
      ? visit.locations.name_ar || visit.locations.name_en
      : visit.locations.name_en
    : "";
  const classification = scoreSummary?.classification ?? null;

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
            {locationName}
          </h1>
          <p className="text-sm text-zinc-500 dark:text-zinc-400">
            {visit.visit_date} · {visit.profiles?.full_name ?? "—"}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2 text-lg">
            <span>
              {scoreSummary?.overall_pct !== null &&
              scoreSummary?.overall_pct !== undefined
                ? `${scoreSummary.overall_pct}%`
                : "—"}
            </span>
            {classification && (
              <Pill tone={classificationTone(classification)}>
                {classification}
              </Pill>
            )}
          </div>
          {isAdmin && !editing && (
            <div className="flex gap-2">
              <button
                type="button"
                onClick={startEdit}
                className="h-9 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
              >
                {t.editValue}
              </button>
              {confirmingDelete ? (
                <>
                  <span className="flex items-center text-sm text-red-600">
                    {t.confirmDeleteVisit}
                  </span>
                  <button
                    type="button"
                    onClick={handleDelete}
                    disabled={deleting}
                    className="h-9 rounded-md bg-red-600 px-3 text-sm font-medium text-white disabled:opacity-60"
                  >
                    {deleting ? t.savingValue : t.confirmDeleteValue}
                  </button>
                  <button
                    type="button"
                    onClick={() => setConfirmingDelete(false)}
                    className="h-9 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
                  >
                    {t.cancelEdit}
                  </button>
                </>
              ) : (
                <button
                  type="button"
                  onClick={() => setConfirmingDelete(true)}
                  className="h-9 rounded-md border border-red-300 px-3 text-sm font-medium text-red-600 dark:border-red-900"
                >
                  {t.deleteVisit}
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      {editing ? (
        <div className="flex flex-wrap gap-4">
          <label className="flex flex-col gap-1 text-sm">
            {t.visitDateLabel}
            <input
              type="date"
              value={editVisitDate}
              onChange={(e) => setEditVisitDate(e.target.value)}
              className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>
          <label className="flex flex-1 flex-col gap-1 text-sm">
            {t.generalNotesLabel}
            <textarea
              value={editNotes}
              onChange={(e) => setEditNotes(e.target.value)}
              rows={2}
              className="rounded-md border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>
        </div>
      ) : (
        visit.notes && (
          <p className="rounded-md border border-zinc-200 p-3 text-sm dark:border-zinc-800">
            {visit.notes}
          </p>
        )
      )}

      {categoryGroups.map((group) => (
        <section key={group.categoryId} className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">{group.categoryName}</h2>
          <div className="flex flex-col divide-y divide-zinc-100 rounded-md border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {group.rows.map((row) => {
              const editAnswer = editAnswers[row.id];
              return (
                <div key={row.id} className="flex flex-col gap-2 p-3">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <p className="text-sm font-medium">
                      {row.audit_items?.label}
                    </p>
                    {editing ? (
                      <div className="flex shrink-0 gap-1">
                        {(
                          [
                            { value: 1 as const, label: t.scorePass },
                            { value: 0 as const, label: t.scoreFail },
                            { value: null, label: t.scoreNa },
                          ] satisfies { value: 0 | 1 | null; label: string }[]
                        ).map((opt) => (
                          <button
                            key={String(opt.value)}
                            type="button"
                            onClick={() => setEditScore(row.id, opt.value)}
                            className={`h-9 rounded-md border px-3 text-xs font-medium ${
                              editAnswer?.score === opt.value
                                ? opt.value === 1
                                  ? "border-green-600 bg-green-600 text-white"
                                  : opt.value === 0
                                    ? "border-red-600 bg-red-600 text-white"
                                    : "border-zinc-500 bg-zinc-500 text-white"
                                : "border-zinc-300 dark:border-zinc-700"
                            }`}
                          >
                            {opt.label}
                          </button>
                        ))}
                      </div>
                    ) : (
                      <Pill tone={scoreTone(row.score)}>
                        {row.score === 1
                          ? t.scorePass
                          : row.score === 0
                            ? t.scoreFail
                            : t.scoreNa}
                      </Pill>
                    )}
                  </div>
                  {editing ? (
                    editAnswer?.score === 0 && (
                      <input
                        type="text"
                        value={editAnswer.note}
                        onChange={(e) => setEditNote(row.id, e.target.value)}
                        placeholder={t.noteOptional}
                        className="h-9 rounded-md border border-zinc-300 px-3 text-sm dark:border-zinc-700 dark:bg-zinc-900"
                      />
                    )
                  ) : (
                    <>
                      {row.note && (
                        <p className="text-xs text-zinc-500 dark:text-zinc-400">
                          {row.note}
                        </p>
                      )}
                      {row.evidence_urls && row.evidence_urls.length > 0 && (
                        <div className="flex flex-wrap gap-2">
                          {row.evidence_urls.map((path) => (
                            <button
                              key={path}
                              type="button"
                              onClick={() => handleViewEvidence(path)}
                              className="text-fluffy-orange text-xs font-medium"
                            >
                              {t.evidenceAttached}
                            </button>
                          ))}
                        </div>
                      )}
                    </>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      ))}

      {editing && (
        <div className="flex gap-2">
          <button
            type="button"
            onClick={handleSaveEdit}
            disabled={saving}
            className="bg-fluffy-orange h-11 w-fit rounded-md px-6 text-base font-medium text-white disabled:opacity-60"
          >
            {saving ? t.savingValue : t.saveVisit}
          </button>
          <button
            type="button"
            onClick={() => setEditing(false)}
            className="h-11 w-fit rounded-md border border-zinc-300 px-4 text-base font-medium dark:border-zinc-700"
          >
            {t.cancelEdit}
          </button>
        </div>
      )}

      {actions.length > 0 && (
        <section className="flex flex-col gap-2">
          <h2 className="text-lg font-semibold">{t.correctiveActionsTitle}</h2>
          <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.descriptionLabel}</th>
                  <th className="p-2 text-center">{t.statusLabel}</th>
                </tr>
              </thead>
              <tbody>
                {actions.map((action) => (
                  <tr
                    key={action.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{action.description}</td>
                    <td className="p-2 text-center">
                      <Pill tone={ACTION_STATUS_TONE[action.status] ?? "zinc"}>
                        {action.status === "open"
                          ? t.statusOpen
                          : action.status === "in_progress"
                            ? t.statusInProgress
                            : t.statusClosed}
                      </Pill>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Link
            to={`/corrective-actions?visit_id=${visit.id}`}
            className="text-fluffy-orange w-fit text-sm font-medium"
          >
            {t.reviewCorrectiveActions}
          </Link>
        </section>
      )}
    </div>
  );
}

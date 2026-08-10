import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useAuditLocations } from "@/lib/location/useAuditLocations";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Pill } from "@/components/Pill";

type CategoryWithItems = Tables<"audit_categories"> & {
  audit_items: Tables<"audit_items">[];
};

type Answer = {
  score: 0 | 1 | null;
  touched: boolean;
  note: string;
  evidenceUrls: string[];
};

type Draft = {
  locationId: string;
  visitDate: string;
  notes: string;
  answers: Record<string, Answer>;
};

const DRAFT_KEY = "fluffy-audit-draft-v1";

function loadDraft(): Draft | null {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    return raw ? (JSON.parse(raw) as Draft) : null;
  } catch {
    return null;
  }
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function classify(pct: number | null) {
  if (pct === null) return null;
  if (pct >= 90) return { label: "ممتاز", tone: "green" as const };
  if (pct >= 80) return { label: "يحتاج تحسين", tone: "amber" as const };
  return { label: "يحتاج تدخل إداري", tone: "red" as const };
}

export function AuditEntryPage() {
  const { profile } = useAuth();
  const { t } = useLocale();
  const locations = useAuditLocations();
  const navigate = useNavigate();

  const canWrite =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "inspector";

  const [categories, setCategories] = useState<CategoryWithItems[]>([]);
  const [initialDraft] = useState(loadDraft);
  const [draftRestored, setDraftRestored] = useState(initialDraft !== null);
  const [locationId, setLocationId] = useState(initialDraft?.locationId ?? "");
  const [visitDate, setVisitDate] = useState(
    initialDraft?.visitDate ?? todayIso()
  );
  const [notes, setNotes] = useState(initialDraft?.notes ?? "");
  const [answers, setAnswers] = useState<Record<string, Answer>>(
    initialDraft?.answers ?? {}
  );
  const [uploadingItemId, setUploadingItemId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [savedVisitId, setSavedVisitId] = useState<string | null>(null);

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
    supabase
      .from("audit_categories")
      .select("*, audit_items(*)")
      .eq("active", true)
      .eq("audit_items.active", true)
      .order("sort_order")
      .order("sort_order", { foreignTable: "audit_items" })
      .then(({ data, error: fetchError }) => {
        if (fetchError) {
          console.error("Load audit criteria failed:", fetchError);
          return;
        }
        setCategories((data as CategoryWithItems[] | null) ?? []);
      });
  }, []);

  // Autosave the in-progress checklist to localStorage so closing the
  // browser or navigating away before hitting Save doesn't lose the work.
  useEffect(() => {
    if (savedVisitId) return;
    const hasContent = Object.keys(answers).length > 0 || notes.trim();
    if (!hasContent) {
      localStorage.removeItem(DRAFT_KEY);
      return;
    }
    const draft: Draft = { locationId, visitDate, notes, answers };
    localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
  }, [locationId, visitDate, notes, answers, savedVisitId]);

  const allItems = useMemo(
    () => categories.flatMap((c) => c.audit_items),
    [categories]
  );

  function setAnswer(itemId: string, score: 0 | 1 | null) {
    setAnswers((prev) => ({
      ...prev,
      [itemId]: {
        score,
        touched: true,
        note: prev[itemId]?.note ?? "",
        evidenceUrls: prev[itemId]?.evidenceUrls ?? [],
      },
    }));
  }

  function setNote(itemId: string, note: string) {
    setAnswers((prev) => ({
      ...prev,
      [itemId]: {
        score: prev[itemId]?.score ?? null,
        touched: prev[itemId]?.touched ?? false,
        note,
        evidenceUrls: prev[itemId]?.evidenceUrls ?? [],
      },
    }));
  }

  function applyCategoryScore(
    category: CategoryWithItems,
    score: 0 | 1 | null
  ) {
    setAnswers((prev) => {
      const next = { ...prev };
      for (const item of category.audit_items) {
        next[item.id] = {
          score,
          touched: true,
          note: prev[item.id]?.note ?? "",
          evidenceUrls: prev[item.id]?.evidenceUrls ?? [],
        };
      }
      return next;
    });
  }

  async function handleEvidenceUpload(itemId: string, file: File) {
    if (!locationId) {
      setError(t.selectBranchFirst);
      return;
    }
    setUploadingItemId(itemId);
    setError(null);
    const ext = file.name.includes(".") ? file.name.split(".").pop() : "bin";
    const path = `${locationId}/${crypto.randomUUID()}.${ext}`;
    const { error: uploadError } = await supabase.storage
      .from("audit-evidence")
      .upload(path, file);
    setUploadingItemId(null);

    if (uploadError) {
      console.error("Upload evidence failed:", uploadError);
      setError(uploadError.message);
      return;
    }

    setAnswers((prev) => ({
      ...prev,
      [itemId]: {
        score: prev[itemId]?.score ?? null,
        touched: prev[itemId]?.touched ?? false,
        note: prev[itemId]?.note ?? "",
        evidenceUrls: [...(prev[itemId]?.evidenceUrls ?? []), path],
      },
    }));
  }

  function removeEvidence(itemId: string, path: string) {
    setAnswers((prev) => ({
      ...prev,
      [itemId]: {
        ...prev[itemId],
        evidenceUrls: (prev[itemId]?.evidenceUrls ?? []).filter(
          (p) => p !== path
        ),
      },
    }));
    void supabase.storage.from("audit-evidence").remove([path]);
  }

  function discardDraft() {
    localStorage.removeItem(DRAFT_KEY);
    setDraftRestored(false);
    setAnswers({});
    setNotes("");
    setVisitDate(todayIso());
  }

  const { scoredCount, passedCount, failedItems, overallPct } = useMemo(() => {
    let scored = 0;
    let passed = 0;
    const failed: Tables<"audit_items">[] = [];
    for (const item of allItems) {
      const a = answers[item.id];
      if (!a || !a.touched || a.score === null) continue;
      scored += 1;
      if (a.score === 1) passed += 1;
      else failed.push(item);
    }
    return {
      scoredCount: scored,
      passedCount: passed,
      failedItems: failed,
      overallPct:
        scored === 0 ? null : Math.round((passed / scored) * 1000) / 10,
    };
  }, [allItems, answers]);

  const classification = classify(overallPct);

  if (!canWrite) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleSave() {
    setError(null);

    if (!locationId) {
      setError(t.selectBranchFirst);
      return;
    }
    if (scoredCount === 0) {
      setError(t.scoreAtLeastOneItem);
      return;
    }

    const p_scores = allItems
      .filter((item) => answers[item.id]?.touched)
      .map((item) => {
        const a = answers[item.id];
        return {
          item_id: item.id,
          score: a.score,
          note: a.note.trim() || null,
          evidence_urls: a.evidenceUrls.length > 0 ? a.evidenceUrls : undefined,
        };
      });

    setSaving(true);
    const { data, error: rpcError } = await supabase.rpc("record_audit_visit", {
      p_location_id: locationId,
      p_visit_date: visitDate,
      p_notes: notes.trim() || undefined,
      p_scores,
    });
    setSaving(false);

    if (rpcError) {
      console.error("Record audit visit failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    localStorage.removeItem(DRAFT_KEY);
    setSavedVisitId(data as string);
  }

  if (savedVisitId) {
    return (
      <div className="flex flex-1 flex-col gap-6 p-6">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.auditSavedTitle}
        </h1>
        <div className="flex items-center gap-3 text-lg">
          <span>{overallPct}%</span>
          {classification && (
            <Pill tone={classification.tone}>{classification.label}</Pill>
          )}
        </div>

        {failedItems.length > 0 && (
          <section className="flex flex-col gap-2">
            <h2 className="text-lg font-semibold">{t.failedItemsTitle}</h2>
            <ul className="flex flex-col gap-1 text-sm">
              {failedItems.map((item) => (
                <li key={item.id}>• {item.label}</li>
              ))}
            </ul>
            <p className="text-xs text-zinc-500 dark:text-zinc-400">
              {t.correctiveActionsAutoCreatedNote}
            </p>
            <button
              type="button"
              onClick={() =>
                navigate(`/corrective-actions?visit_id=${savedVisitId}`)
              }
              className="bg-fluffy-orange mt-2 h-11 w-fit rounded-md px-4 text-sm font-medium text-white"
            >
              {t.reviewCorrectiveActions}
            </button>
          </section>
        )}

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => navigate(`/audit-visit/${savedVisitId}`)}
            className="h-11 w-fit rounded-md border border-zinc-300 px-4 text-sm font-medium dark:border-zinc-700"
          >
            {t.viewVisitDetails}
          </button>
          <button
            type="button"
            onClick={() => {
              setSavedVisitId(null);
              setAnswers({});
              setNotes("");
              setVisitDate(todayIso());
            }}
            className="h-11 w-fit rounded-md border border-zinc-300 px-4 text-sm font-medium dark:border-zinc-700"
          >
            {t.startNewVisit}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6 pb-36">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.auditEntryTitle}
        </h1>
        {overallPct !== null && (
          <div className="flex items-center gap-2 text-sm">
            <span className="font-semibold">{overallPct}%</span>
            {classification && (
              <Pill tone={classification.tone}>{classification.label}</Pill>
            )}
            <span className="text-zinc-500">
              ({passedCount}/{scoredCount})
            </span>
          </div>
        )}
      </div>

      {draftRestored && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm dark:border-amber-800 dark:bg-amber-950">
          <span>{t.draftRestoredNote}</span>
          <button
            type="button"
            onClick={discardDraft}
            className="text-fluffy-orange font-medium"
          >
            {t.discardDraft}
          </button>
        </div>
      )}

      <div className="flex flex-wrap gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.branchTypeLabel}
          {locations.length === 0 ? (
            <span className="h-11 rounded-md border border-zinc-300 px-3 py-2 text-zinc-500 dark:border-zinc-700">
              {t.selectBranchFirst}
            </span>
          ) : (
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
          )}
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {t.visitDateLabel}
          <input
            type="date"
            value={visitDate}
            onChange={(e) => setVisitDate(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>
      </div>

      {categories.map((category) => (
        <section key={category.id} className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-lg font-semibold">{category.name}</h2>
            <div className="flex gap-1">
              <button
                type="button"
                onClick={() => applyCategoryScore(category, 1)}
                className="h-8 rounded-md border border-green-600 px-2 text-xs font-medium text-green-600"
              >
                {t.applyPassAll}
              </button>
              <button
                type="button"
                onClick={() => applyCategoryScore(category, 0)}
                className="h-8 rounded-md border border-red-600 px-2 text-xs font-medium text-red-600"
              >
                {t.applyFailAll}
              </button>
              <button
                type="button"
                onClick={() => applyCategoryScore(category, null)}
                className="h-8 rounded-md border border-zinc-500 px-2 text-xs font-medium text-zinc-500"
              >
                {t.applyNaAll}
              </button>
            </div>
          </div>
          <div className="flex flex-col divide-y divide-zinc-100 rounded-md border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {category.audit_items.map((item) => {
              const a = answers[item.id];
              return (
                <div key={item.id} className="flex flex-col gap-2 p-3">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <p className="text-sm font-medium">{item.label}</p>
                      {item.definition && (
                        <p className="text-xs text-zinc-500 dark:text-zinc-400">
                          {item.definition}
                        </p>
                      )}
                    </div>
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
                          onClick={() => setAnswer(item.id, opt.value)}
                          className={`h-9 rounded-md border px-3 text-xs font-medium ${
                            a?.touched && a.score === opt.value
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
                  </div>
                  {a?.touched && a.score === 0 && (
                    <div className="flex flex-col gap-2">
                      <input
                        type="text"
                        value={a.note}
                        onChange={(e) => setNote(item.id, e.target.value)}
                        placeholder={t.noteOptional}
                        className="h-9 rounded-md border border-zinc-300 px-3 text-sm dark:border-zinc-700 dark:bg-zinc-900"
                      />
                      <div className="flex flex-wrap items-center gap-2">
                        <label className="text-fluffy-orange cursor-pointer text-xs font-medium">
                          {uploadingItemId === item.id
                            ? t.uploadingEvidence
                            : t.attachEvidence}
                          <input
                            type="file"
                            accept="image/*"
                            className="hidden"
                            disabled={uploadingItemId === item.id}
                            onChange={(e) => {
                              const file = e.target.files?.[0];
                              if (file) handleEvidenceUpload(item.id, file);
                              e.target.value = "";
                            }}
                          />
                        </label>
                        {a.evidenceUrls.map((path) => (
                          <span
                            key={path}
                            className="flex items-center gap-1 rounded-full border border-zinc-300 px-2 py-1 text-xs dark:border-zinc-700"
                          >
                            {t.evidenceAttached}
                            <button
                              type="button"
                              onClick={() => removeEvidence(item.id, path)}
                              aria-label={t.removeLine}
                              className="text-red-600"
                            >
                              ×
                            </button>
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      ))}

      <label className="flex flex-col gap-1 text-sm">
        {t.generalNotesLabel}
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={3}
          className="rounded-md border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
        />
      </label>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <div className="fixed inset-x-0 bottom-16 flex justify-end border-t border-zinc-200 bg-white p-4 md:bottom-0 dark:border-zinc-800 dark:bg-zinc-950">
        <button
          type="button"
          onClick={handleSave}
          disabled={saving}
          className="bg-fluffy-orange h-11 rounded-md px-6 text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.savingValue : t.saveVisit}
        </button>
      </div>
    </div>
  );
}

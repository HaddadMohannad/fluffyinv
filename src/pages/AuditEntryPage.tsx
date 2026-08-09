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

type Answer = { score: 0 | 1 | null; touched: boolean; note: string };

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
    profile?.role === "admin" || profile?.role === "branch_manager";

  const [categories, setCategories] = useState<CategoryWithItems[]>([]);
  const [locationId, setLocationId] = useState("");
  const [visitDate, setVisitDate] = useState(todayIso());
  const [notes, setNotes] = useState("");
  const [answers, setAnswers] = useState<Record<string, Answer>>({});
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

  const allItems = useMemo(
    () => categories.flatMap((c) => c.audit_items),
    [categories]
  );

  function setAnswer(itemId: string, score: 0 | 1 | null) {
    setAnswers((prev) => ({
      ...prev,
      [itemId]: { score, touched: true, note: prev[itemId]?.note ?? "" },
    }));
  }

  function setNote(itemId: string, note: string) {
    setAnswers((prev) => ({
      ...prev,
      [itemId]: {
        score: prev[itemId]?.score ?? null,
        touched: prev[itemId]?.touched ?? false,
        note,
      },
    }));
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
            <button
              type="button"
              onClick={() =>
                navigate(`/corrective-actions?visit_id=${savedVisitId}`)
              }
              className="bg-fluffy-orange mt-2 h-11 w-fit rounded-md px-4 text-sm font-medium text-white"
            >
              {t.logCorrectiveActions}
            </button>
          </section>
        )}

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
    );
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6 pb-24">
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
          <h2 className="text-lg font-semibold">{category.name}</h2>
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
                    <input
                      type="text"
                      value={a.note}
                      onChange={(e) => setNote(item.id, e.target.value)}
                      placeholder={t.noteOptional}
                      className="h-9 rounded-md border border-zinc-300 px-3 text-sm dark:border-zinc-700 dark:bg-zinc-900"
                    />
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

      <div className="fixed inset-x-0 bottom-0 flex justify-end border-t border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950">
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

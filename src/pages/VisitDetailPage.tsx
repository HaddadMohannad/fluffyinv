import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router";
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

  const [visit, setVisit] = useState<VisitWithRelations | null>(null);
  const [scoreSummary, setScoreSummary] =
    useState<Tables<"v_audit_visit_scores"> | null>(null);
  const [itemScores, setItemScores] = useState<ItemScoreWithItem[]>([]);
  const [actions, setActions] = useState<Tables<"corrective_actions">[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
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
      </div>

      {visit.notes && (
        <p className="rounded-md border border-zinc-200 p-3 text-sm dark:border-zinc-800">
          {visit.notes}
        </p>
      )}

      {categoryGroups.map((group) => (
        <section key={group.categoryId} className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">{group.categoryName}</h2>
          <div className="flex flex-col divide-y divide-zinc-100 rounded-md border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {group.rows.map((row) => (
              <div key={row.id} className="flex flex-col gap-2 p-3">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <p className="text-sm font-medium">
                    {row.audit_items?.label}
                  </p>
                  <Pill tone={scoreTone(row.score)}>
                    {row.score === 1
                      ? t.scorePass
                      : row.score === 0
                        ? t.scoreFail
                        : t.scoreNa}
                  </Pill>
                </div>
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
              </div>
            ))}
          </div>
        </section>
      ))}

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

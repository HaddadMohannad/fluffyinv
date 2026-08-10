import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Pill } from "@/components/Pill";
import type { PillTone } from "@/lib/pillColors";

type VisitScore = Tables<"v_audit_visit_scores">;

type BranchSummary = {
  locationId: string;
  name: string;
  visitCount: number;
  avgPct: number | null;
  excellent: number;
  needsImprovement: number;
  needsIntervention: number;
  openActions: number;
};

function classificationTone(classification: string | null): PillTone {
  if (classification === "ممتاز") return "green";
  if (classification === "يحتاج تحسين") return "amber";
  return "red";
}

export function QualityDashboardPage() {
  const { t, locale } = useLocale();

  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [visits, setVisits] = useState<VisitScore[]>([]);
  const [openActionCounts, setOpenActionCounts] = useState<
    Record<string, number>
  >({});

  useEffect(() => {
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));

    supabase
      .from("v_audit_visit_scores")
      .select("*")
      .order("visit_date", { ascending: false })
      .then(({ data }) => setVisits((data as VisitScore[] | null) ?? []));

    supabase
      .from("corrective_actions")
      .select("location_id, status")
      .neq("status", "closed")
      .then(({ data }) => {
        const counts: Record<string, number> = {};
        for (const row of data ?? []) {
          if (!row.location_id) continue;
          counts[row.location_id] = (counts[row.location_id] ?? 0) + 1;
        }
        setOpenActionCounts(counts);
      });
  }, []);

  const summaries = useMemo<BranchSummary[]>(() => {
    return locations.map((loc) => {
      const locVisits = visits.filter((v) => v.location_id === loc.id);
      const scored = locVisits.filter((v) => v.overall_pct !== null);
      const avgPct =
        scored.length === 0
          ? null
          : Math.round(
              (scored.reduce((sum, v) => sum + (v.overall_pct ?? 0), 0) /
                scored.length) *
                10
            ) / 10;
      return {
        locationId: loc.id,
        name: locale === "ar" ? loc.name_ar : loc.name_en,
        visitCount: locVisits.length,
        avgPct,
        excellent: locVisits.filter((v) => v.classification === "ممتاز").length,
        needsImprovement: locVisits.filter(
          (v) => v.classification === "يحتاج تحسين"
        ).length,
        needsIntervention: locVisits.filter(
          (v) => v.classification === "يحتاج تدخل إداري"
        ).length,
        openActions: openActionCounts[loc.id] ?? 0,
      };
    });
  }, [locations, visits, openActionCounts, locale]);

  const recentVisits = visits.slice(0, 15);
  const locationName = (id: string) => {
    const loc = locations.find((l) => l.id === id);
    return loc ? (locale === "ar" ? loc.name_ar : loc.name_en) : id;
  };

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.qualityDashboardTitle}
      </h1>

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="w-full min-w-max text-sm">
          <thead className="bg-zinc-50 dark:bg-zinc-900">
            <tr>
              <th className="p-2 text-start">{t.branchTypeLabel}</th>
              <th className="p-2 text-end">{t.visitCountLabel}</th>
              <th className="p-2 text-end">{t.avgScoreLabel}</th>
              <th className="p-2 text-end">{t.excellentCountLabel}</th>
              <th className="p-2 text-end">{t.needsImprovementCountLabel}</th>
              <th className="p-2 text-end">{t.needsInterventionCountLabel}</th>
              <th className="p-2 text-end">{t.openActionsCountLabel}</th>
            </tr>
          </thead>
          <tbody>
            {summaries.map((s) => (
              <tr
                key={s.locationId}
                className="border-t border-zinc-100 dark:border-zinc-800"
              >
                <td className="p-2 font-medium">{s.name}</td>
                <td className="p-2 text-end">{s.visitCount}</td>
                <td className="p-2 text-end">
                  {s.avgPct !== null ? `${s.avgPct}%` : "—"}
                </td>
                <td className="p-2 text-end">{s.excellent}</td>
                <td className="p-2 text-end">{s.needsImprovement}</td>
                <td className="p-2 text-end">{s.needsIntervention}</td>
                <td className="p-2 text-end">
                  {s.openActions > 0 ? (
                    <span className="font-semibold text-amber-600">
                      {s.openActions}
                    </span>
                  ) : (
                    0
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <section>
        <h2 className="mb-2 text-lg font-semibold">{t.recentVisitsTitle}</h2>
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.visitDateLabel}</th>
                <th className="p-2 text-start">{t.branchTypeLabel}</th>
                <th className="p-2 text-end">{t.avgScoreLabel}</th>
                <th className="p-2 text-center">{t.statusLabel}</th>
              </tr>
            </thead>
            <tbody>
              {recentVisits.map((v) => (
                <tr
                  key={v.visit_id}
                  className="border-t border-zinc-100 hover:bg-zinc-50 dark:border-zinc-800 dark:hover:bg-zinc-900"
                >
                  <td className="p-0">
                    <Link
                      to={`/audit-visit/${v.visit_id}`}
                      className="flex p-2"
                    >
                      {v.visit_date}
                    </Link>
                  </td>
                  <td className="p-0">
                    <Link
                      to={`/audit-visit/${v.visit_id}`}
                      className="flex p-2"
                    >
                      {locationName(v.location_id ?? "")}
                    </Link>
                  </td>
                  <td className="p-0">
                    <Link
                      to={`/audit-visit/${v.visit_id}`}
                      className="flex justify-end p-2"
                    >
                      {v.overall_pct !== null ? `${v.overall_pct}%` : "—"}
                    </Link>
                  </td>
                  <td className="p-2 text-center">
                    {v.classification && (
                      <Pill tone={classificationTone(v.classification)}>
                        {v.classification}
                      </Pill>
                    )}
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

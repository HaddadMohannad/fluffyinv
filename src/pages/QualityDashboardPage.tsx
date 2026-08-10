import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Label,
  LabelList,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { Pill } from "@/components/Pill";
import type { PillTone } from "@/lib/pillColors";
import { useIsDarkMode } from "@/lib/useIsDarkMode";
import {
  categoricalColor,
  statusColorForPct,
  CHART_INK_LIGHT,
  CHART_INK_DARK,
} from "@/lib/chartColors";

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

type TrendPoint = { date: string } & Record<string, number | string | null>;

function classificationTone(classification: string | null): PillTone {
  if (classification === "ممتاز") return "green";
  if (classification === "يحتاج تحسين") return "amber";
  return "red";
}

export function QualityDashboardPage() {
  const { t, locale } = useLocale();
  const isDark = useIsDarkMode();
  const ink = isDark ? CHART_INK_DARK : CHART_INK_LIGHT;

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

  // One bar per branch that has at least one scored visit, ranked so
  // branches can be directly compared at a glance.
  const compareData = useMemo(
    () =>
      summaries
        .filter((s) => s.avgPct !== null)
        .sort((a, b) => (b.avgPct ?? 0) - (a.avgPct ?? 0)),
    [summaries]
  );

  // Wide-format trend series: one row per visit date, one column per
  // branch, so each branch draws as its own line and gaps just don't
  // connect rather than reading as zero.
  const trendData = useMemo<TrendPoint[]>(() => {
    const byDate = new Map<string, TrendPoint>();
    for (const v of visits) {
      if (v.overall_pct === null || !v.location_id || !v.visit_date) continue;
      if (!byDate.has(v.visit_date)) {
        byDate.set(v.visit_date, { date: v.visit_date });
      }
      byDate.get(v.visit_date)![v.location_id] = v.overall_pct;
    }
    return Array.from(byDate.values()).sort((a, b) =>
      a.date.localeCompare(b.date)
    );
  }, [visits]);

  const trendLocations = useMemo(
    () =>
      locations.filter((loc) =>
        trendData.some((point) => point[loc.id] !== undefined)
      ),
    [locations, trendData]
  );

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

      {visits.length === 0 ? (
        <p className="rounded-md border border-zinc-200 p-6 text-center text-sm text-zinc-500 dark:border-zinc-800 dark:text-zinc-400">
          {t.noAuditDataYet}
        </p>
      ) : (
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <section className="rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
            <h2 className="mb-3 text-lg font-semibold">
              {t.compareBranchesTitle}
            </h2>
            {compareData.length === 0 ? (
              <p className="text-sm text-zinc-500 dark:text-zinc-400">
                {t.noAuditDataYet}
              </p>
            ) : (
              <ResponsiveContainer
                width="100%"
                height={Math.max(180, compareData.length * 40)}
              >
                <BarChart
                  data={compareData}
                  layout="vertical"
                  margin={{ top: 4, right: 32, bottom: 4, left: 4 }}
                >
                  <CartesianGrid horizontal={false} stroke={ink.gridline} />
                  <XAxis
                    type="number"
                    domain={[0, 100]}
                    ticks={[0, 25, 50, 75, 100]}
                    tick={{ fill: ink.muted, fontSize: 12 }}
                    stroke={ink.baseline}
                  />
                  <YAxis
                    type="category"
                    dataKey="name"
                    width={110}
                    tick={{ fill: ink.secondary, fontSize: 12 }}
                    stroke={ink.baseline}
                  />
                  <Tooltip
                    formatter={(value) => [`${value}%`, t.avgScoreLabel]}
                    contentStyle={{
                      background: isDark ? "#1a1a19" : "#fcfcfb",
                      border: `1px solid ${ink.gridline}`,
                      color: ink.primary,
                      fontSize: 12,
                    }}
                  />
                  <Bar dataKey="avgPct" barSize={20} radius={[0, 4, 4, 0]}>
                    {compareData.map((entry) => (
                      <Cell
                        key={entry.locationId}
                        fill={statusColorForPct(entry.avgPct)}
                      />
                    ))}
                    <LabelList
                      dataKey="avgPct"
                      position="right"
                      formatter={(value) => `${value}%`}
                      style={{ fill: ink.primary, fontSize: 12 }}
                    />
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            )}
          </section>

          <section className="rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
            <h2 className="mb-3 text-lg font-semibold">{t.scoreTrendTitle}</h2>
            {trendData.length === 0 ? (
              <p className="text-sm text-zinc-500 dark:text-zinc-400">
                {t.noAuditDataYet}
              </p>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <LineChart
                  data={trendData}
                  margin={{ top: 4, right: 16, bottom: 4, left: 4 }}
                >
                  <CartesianGrid stroke={ink.gridline} />
                  <XAxis
                    dataKey="date"
                    tick={{ fill: ink.muted, fontSize: 11 }}
                    stroke={ink.baseline}
                  />
                  <YAxis
                    domain={[0, 100]}
                    ticks={[0, 25, 50, 75, 100]}
                    tick={{ fill: ink.muted, fontSize: 12 }}
                    stroke={ink.baseline}
                  >
                    <Label
                      value="%"
                      position="insideTopLeft"
                      fill={ink.muted}
                      fontSize={11}
                    />
                  </YAxis>
                  <Tooltip
                    contentStyle={{
                      background: isDark ? "#1a1a19" : "#fcfcfb",
                      border: `1px solid ${ink.gridline}`,
                      color: ink.primary,
                      fontSize: 12,
                    }}
                  />
                  <Legend
                    wrapperStyle={{ fontSize: 12, color: ink.secondary }}
                  />
                  {trendLocations.map((loc, index) => (
                    <Line
                      key={loc.id}
                      dataKey={loc.id}
                      name={locale === "ar" ? loc.name_ar : loc.name_en}
                      stroke={categoricalColor(index, isDark)}
                      strokeWidth={2}
                      dot={{ r: 4 }}
                      connectNulls
                    />
                  ))}
                </LineChart>
              </ResponsiveContainer>
            )}
          </section>
        </div>
      )}

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

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { downloadCsv } from "@/lib/exportCsv";
import type { Enums, Tables } from "@/lib/supabase/database.types";

type DaySummary = {
  day: string;
  orders: number;
  gross: number;
  commission: number;
  net: number;
};

type SalesSource = Enums<"sales_source">;

const SOURCES: SalesSource[] = [
  "talabat",
  "careem",
  "foodics",
  "manual",
  "pos",
];

export function SalesDashboardPage() {
  const { t } = useLocale();
  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [byDay, setByDay] = useState<DaySummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [exporting, setExporting] = useState(false);

  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [locationId, setLocationId] = useState("");
  const [source, setSource] = useState<SalesSource | "">("");

  useEffect(() => {
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
  }, []);

  useEffect(() => {
    let active = true;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- standard fetch-on-mount/dep-change loading flag
    setLoading(true);
    setError(null);

    // Aggregated server-side (one row per day, not per order) -- a raw
    // per-order select() here gets silently capped at 1000 rows by
    // PostgREST once a filter matches more than that, which understated
    // totals as soon as real order volume passed four figures.
    supabase
      .rpc("sales_dashboard_summary", {
        p_date_from: dateFrom || undefined,
        p_date_to: dateTo || undefined,
        p_location_id: locationId || undefined,
        p_source: source || undefined,
      })
      .then(({ data, error: queryError }) => {
        if (!active) return;
        if (queryError) {
          setError(queryError.message);
        } else {
          setByDay(data ?? []);
        }
        setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [dateFrom, dateTo, locationId, source]);

  const locationName = useMemo(() => {
    const map = new Map(locations.map((l) => [l.id, l.name_en]));
    return (id: string) => map.get(id) ?? id;
  }, [locations]);

  const totals = useMemo(
    () =>
      byDay.reduce(
        (acc, d) => ({
          gross: acc.gross + d.gross,
          commission: acc.commission + d.commission,
          net: acc.net + d.net,
          orders: acc.orders + d.orders,
        }),
        { gross: 0, commission: 0, net: 0, orders: 0 }
      ),
    [byDay]
  );

  async function handleExport() {
    setExporting(true);
    try {
      // The per-order CSV needs raw rows, unlike the aggregated totals
      // above -- page through with .range() so an export matching more
      // than 1000 orders isn't silently truncated either.
      const pageSize = 1000;
      const allRows: Pick<
        Tables<"sales_orders">,
        "order_date" | "source" | "location_id" | "gross" | "commission" | "net"
      >[] = [];
      for (let page = 0; ; page++) {
        let query = supabase
          .from("sales_orders")
          .select("order_date, source, location_id, gross, commission, net")
          .order("id", { ascending: true })
          .range(page * pageSize, page * pageSize + pageSize - 1);

        if (dateFrom) query = query.gte("order_date", dateFrom);
        if (dateTo) query = query.lte("order_date", dateTo);
        if (locationId) query = query.eq("location_id", locationId);
        if (source) query = query.eq("source", source);

        const { data, error: queryError } = await query;
        if (queryError) {
          setError(queryError.message);
          return;
        }
        allRows.push(...(data ?? []));
        if (!data || data.length < pageSize) break;
      }

      downloadCsv(
        "sales-export.csv",
        ["Date", "Source", "Branch", "Gross", "Commission", "Net"],
        allRows.map((r) => [
          r.order_date,
          r.source,
          locationName(r.location_id),
          r.gross,
          r.commission,
          r.net,
        ])
      );
    } finally {
      setExporting(false);
    }
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.salesDashboardTitle}
        </h1>
        <button
          type="button"
          onClick={handleExport}
          disabled={totals.orders === 0 || exporting}
          className="h-11 rounded-md border border-zinc-300 px-4 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
        >
          {exporting ? t.loadingSales : t.exportCsv}
        </button>
      </div>

      <div className="flex flex-wrap gap-3">
        <label className="flex flex-col gap-1 text-sm">
          {t.dateFrom}
          <input
            type="date"
            value={dateFrom}
            onChange={(e) => setDateFrom(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {t.dateTo}
          <input
            type="date"
            value={dateTo}
            onChange={(e) => setDateTo(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          &nbsp;
          <select
            value={locationId}
            onChange={(e) => setLocationId(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="">{t.allBranches}</option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {l.name_en}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          &nbsp;
          <select
            value={source}
            onChange={(e) => setSource(e.target.value as SalesSource | "")}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="">{t.allSources}</option>
            {SOURCES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </label>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <Stat label={t.totalOrders} value={totals.orders} />
        <Stat label={t.totalGross} value={totals.gross.toFixed(2)} />
        <Stat label={t.totalCommission} value={totals.commission.toFixed(2)} />
        <Stat label={t.totalNet} value={totals.net.toFixed(2)} />
      </dl>

      {loading ? (
        <p className="text-sm text-zinc-500">{t.loadingSales}</p>
      ) : byDay.length === 0 ? (
        <p className="text-sm text-zinc-500">{t.noResults}</p>
      ) : (
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.dateColumn}</th>
                <th className="p-2 text-end">{t.totalOrders}</th>
                <th className="p-2 text-end">{t.totalGross}</th>
                <th className="p-2 text-end">{t.totalCommission}</th>
                <th className="p-2 text-end">{t.totalNet}</th>
              </tr>
            </thead>
            <tbody>
              {byDay.map((d) => (
                <tr
                  key={d.day}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="p-2">{d.day}</td>
                  <td className="p-2 text-end">{d.orders}</td>
                  <td className="p-2 text-end">{d.gross.toFixed(2)}</td>
                  <td className="p-2 text-end">{d.commission.toFixed(2)}</td>
                  <td className="p-2 text-end">{d.net.toFixed(2)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
      <dt className="text-xs text-zinc-500">{label}</dt>
      <dd className="text-lg font-semibold">{value}</dd>
    </div>
  );
}

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { downloadCsv } from "@/lib/exportCsv";
import type { Enums, Tables } from "@/lib/supabase/database.types";

type SalesSource = Enums<"sales_source">;

const SOURCES: SalesSource[] = ["talabat", "careem", "foodics", "manual", "pos"];

type BranchStats = {
  locationId: string;
  orders: number;
  gross: number;
  net: number;
  waste: number;
  hospitality: number;
  stockValue: number;
};

type SalesRow = {
  location_id: string;
  order_date: string;
  source: SalesSource;
  gross: number;
  net: number;
};

function startOfDayIso(dateStr: string) {
  return `${dateStr}T00:00:00`;
}

function endOfDayIso(dateStr: string) {
  return `${dateStr}T23:59:59`;
}

export function BranchComparisonPage() {
  const { t, locale } = useLocale();

  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [stock, setStock] = useState<
    { location_id: string; product_id: string; qty: number }[]
  >([]);
  const [salesRows, setSalesRows] = useState<SalesRow[]>([]);
  const [wasteRows, setWasteRows] = useState<
    { location_id: string; value_lost: number; created_at: string }[]
  >([]);
  const [hospitalityRows, setHospitalityRows] = useState<
    { location_id: string; value: number; created_at: string }[]
  >([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
    supabase
      .from("products")
      .select("*")
      .then(({ data }) => setProducts(data ?? []));
    supabase
      .from("v_current_stock")
      .select("location_id, product_id, qty")
      .then(({ data }) => {
        setStock(
          (data ?? []).filter(
            (r): r is { location_id: string; product_id: string; qty: number } =>
              r.location_id !== null && r.product_id !== null && r.qty !== null
          )
        );
      });
  }, []);

  useEffect(() => {
    let active = true;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- standard fetch-on-mount/dep-change loading flag
    setLoading(true);
    setError(null);

    let salesQuery = supabase
      .from("sales_orders")
      .select("location_id, order_date, source, gross, net");
    let wasteQuery = supabase
      .from("waste_records")
      .select("location_id, value_lost, created_at");
    let hospitalityQuery = supabase
      .from("hospitality_records")
      .select("location_id, value, created_at");

    if (dateFrom) {
      salesQuery = salesQuery.gte("order_date", dateFrom);
      wasteQuery = wasteQuery.gte("created_at", startOfDayIso(dateFrom));
      hospitalityQuery = hospitalityQuery.gte(
        "created_at",
        startOfDayIso(dateFrom)
      );
    }
    if (dateTo) {
      salesQuery = salesQuery.lte("order_date", dateTo);
      wasteQuery = wasteQuery.lte("created_at", endOfDayIso(dateTo));
      hospitalityQuery = hospitalityQuery.lte(
        "created_at",
        endOfDayIso(dateTo)
      );
    }
    if (locationId) {
      salesQuery = salesQuery.eq("location_id", locationId);
      wasteQuery = wasteQuery.eq("location_id", locationId);
      hospitalityQuery = hospitalityQuery.eq("location_id", locationId);
    }
    if (source) {
      salesQuery = salesQuery.eq("source", source);
    }

    Promise.all([salesQuery, wasteQuery, hospitalityQuery]).then(
      ([salesRes, wasteRes, hospitalityRes]) => {
        if (!active) return;
        const firstError =
          salesRes.error ?? wasteRes.error ?? hospitalityRes.error;
        if (firstError) {
          setError(firstError.message);
        } else {
          setSalesRows(salesRes.data ?? []);
          setWasteRows(wasteRes.data ?? []);
          setHospitalityRows(hospitalityRes.data ?? []);
        }
        setLoading(false);
      }
    );

    return () => {
      active = false;
    };
  }, [dateFrom, dateTo, locationId, source]);

  const avgCostByProduct = useMemo(
    () => new Map(products.map((p) => [p.id, p.avg_cost])),
    [products]
  );

  const stats = useMemo(() => {
    const byLocation = new Map<string, BranchStats>();
    function get(id: string): BranchStats {
      let s = byLocation.get(id);
      if (!s) {
        s = {
          locationId: id,
          orders: 0,
          gross: 0,
          net: 0,
          waste: 0,
          hospitality: 0,
          stockValue: 0,
        };
        byLocation.set(id, s);
      }
      return s;
    }

    for (const r of salesRows) {
      const s = get(r.location_id);
      s.orders += 1;
      s.gross += r.gross;
      s.net += r.net;
    }
    for (const r of wasteRows) {
      get(r.location_id).waste += r.value_lost;
    }
    for (const r of hospitalityRows) {
      get(r.location_id).hospitality += r.value;
    }
    for (const r of stock) {
      if (locationId && r.location_id !== locationId) continue;
      const cost = avgCostByProduct.get(r.product_id) ?? 0;
      get(r.location_id).stockValue += r.qty * cost;
    }

    return Array.from(byLocation.values()).sort((a, b) => b.net - a.net);
  }, [salesRows, wasteRows, hospitalityRows, stock, avgCostByProduct, locationId]);

  const locationName = useMemo(() => {
    const map = new Map(
      locations.map((l) => [l.id, locale === "ar" ? l.name_ar : l.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [locations, locale]);

  const totals = useMemo(
    () =>
      stats.reduce(
        (acc, s) => ({
          orders: acc.orders + s.orders,
          gross: acc.gross + s.gross,
          net: acc.net + s.net,
          waste: acc.waste + s.waste,
          hospitality: acc.hospitality + s.hospitality,
          stockValue: acc.stockValue + s.stockValue,
        }),
        { orders: 0, gross: 0, net: 0, waste: 0, hospitality: 0, stockValue: 0 }
      ),
    [stats]
  );

  // Deep-dive detail, shown only once the view is narrowed to a single branch.
  const byDay = useMemo(() => {
    if (!locationId) return [];
    const map = new Map<
      string,
      { orders: number; gross: number; net: number; waste: number; hospitality: number }
    >();
    function get(day: string) {
      let d = map.get(day);
      if (!d) {
        d = { orders: 0, gross: 0, net: 0, waste: 0, hospitality: 0 };
        map.set(day, d);
      }
      return d;
    }
    for (const r of salesRows) {
      const d = get(r.order_date.slice(0, 10));
      d.orders += 1;
      d.gross += r.gross;
      d.net += r.net;
    }
    for (const r of wasteRows) {
      get(r.created_at.slice(0, 10)).waste += r.value_lost;
    }
    for (const r of hospitalityRows) {
      get(r.created_at.slice(0, 10)).hospitality += r.value;
    }
    return Array.from(map.entries()).sort(([a], [b]) => b.localeCompare(a));
  }, [locationId, salesRows, wasteRows, hospitalityRows]);

  const bySource = useMemo(() => {
    if (!locationId) return [];
    const map = new Map<SalesSource, { orders: number; gross: number; net: number }>();
    for (const r of salesRows) {
      const existing = map.get(r.source) ?? { orders: 0, gross: 0, net: 0 };
      existing.orders += 1;
      existing.gross += r.gross;
      existing.net += r.net;
      map.set(r.source, existing);
    }
    return Array.from(map.entries()).sort(([, a], [, b]) => b.net - a.net);
  }, [locationId, salesRows]);

  function pct(part: number, whole: number) {
    return whole > 0 ? `${((part / whole) * 100).toFixed(1)}%` : "—";
  }

  function handleExport() {
    downloadCsv(
      "branch-comparison.csv",
      [
        t.branchColumn,
        t.totalOrders,
        t.totalGross,
        t.totalNet,
        t.wasteColumn,
        t.wastePctColumn,
        t.hospitalityColumn,
        t.hospitalityPctColumn,
        t.currentStockValueColumn,
      ],
      stats.map((s) => [
        locationName(s.locationId),
        s.orders,
        s.gross.toFixed(2),
        s.net.toFixed(2),
        s.waste.toFixed(2),
        pct(s.waste, s.gross),
        s.hospitality.toFixed(2),
        pct(s.hospitality, s.gross),
        s.stockValue.toFixed(2),
      ])
    );
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.branchComparisonTitle}
        </h1>
        <button
          type="button"
          onClick={handleExport}
          disabled={stats.length === 0}
          className="h-11 rounded-md border border-zinc-300 px-4 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
        >
          {t.exportCsv}
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
                {locale === "ar" ? l.name_ar : l.name_en}
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

      <p className="text-xs text-zinc-500 dark:text-zinc-400">
        {t.stockTurnoverNote}
      </p>

      {loading ? (
        <p className="text-sm text-zinc-500">{t.loadingSales}</p>
      ) : stats.length === 0 ? (
        <p className="text-sm text-zinc-500">{t.noResults}</p>
      ) : (
        <>
          <section>
            <h2 className="mb-2 text-lg font-semibold">
              {t.branchComparisonTitle}
            </h2>
            <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              <table className="w-full min-w-max text-sm">
                <thead className="bg-zinc-50 dark:bg-zinc-900">
                  <tr>
                    <th className="p-2 text-start">{t.branchColumn}</th>
                    <th className="p-2 text-end">{t.totalOrders}</th>
                    <th className="p-2 text-end">{t.totalGross}</th>
                    <th className="p-2 text-end">{t.totalNet}</th>
                    <th className="p-2 text-end">{t.wasteColumn}</th>
                    <th className="p-2 text-end">{t.wastePctColumn}</th>
                    <th className="p-2 text-end">{t.hospitalityColumn}</th>
                    <th className="p-2 text-end">{t.hospitalityPctColumn}</th>
                    <th className="p-2 text-end">
                      {t.currentStockValueColumn}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {stats.map((s) => (
                    <tr
                      key={s.locationId}
                      className={`border-t border-zinc-100 dark:border-zinc-800 ${
                        locationId === s.locationId
                          ? "bg-orange-50 dark:bg-orange-950/30"
                          : ""
                      }`}
                    >
                      <td className="p-2 font-medium">
                        <button
                          type="button"
                          onClick={() =>
                            setLocationId(
                              locationId === s.locationId ? "" : s.locationId
                            )
                          }
                          className="hover:underline"
                        >
                          {locationName(s.locationId)}
                        </button>
                      </td>
                      <td className="p-2 text-end">{s.orders}</td>
                      <td className="p-2 text-end">{s.gross.toFixed(2)}</td>
                      <td className="p-2 text-end">{s.net.toFixed(2)}</td>
                      <td className="p-2 text-end">{s.waste.toFixed(2)}</td>
                      <td className="p-2 text-end">
                        {pct(s.waste, s.gross)}
                      </td>
                      <td className="p-2 text-end">
                        {s.hospitality.toFixed(2)}
                      </td>
                      <td className="p-2 text-end">
                        {pct(s.hospitality, s.gross)}
                      </td>
                      <td className="p-2 text-end">
                        {s.stockValue.toFixed(2)}
                      </td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-zinc-300 font-semibold dark:border-zinc-700">
                  <tr>
                    <td className="p-2">{t.totalsRowLabel}</td>
                    <td className="p-2 text-end">{totals.orders}</td>
                    <td className="p-2 text-end">{totals.gross.toFixed(2)}</td>
                    <td className="p-2 text-end">{totals.net.toFixed(2)}</td>
                    <td className="p-2 text-end">{totals.waste.toFixed(2)}</td>
                    <td className="p-2 text-end">
                      {pct(totals.waste, totals.gross)}
                    </td>
                    <td className="p-2 text-end">
                      {totals.hospitality.toFixed(2)}
                    </td>
                    <td className="p-2 text-end">
                      {pct(totals.hospitality, totals.gross)}
                    </td>
                    <td className="p-2 text-end">
                      {totals.stockValue.toFixed(2)}
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </section>

          {locationId && (
            <>
              <section>
                <h2 className="mb-2 text-lg font-semibold">
                  {locationName(locationId)} — {t.dateColumn}
                </h2>
                {byDay.length === 0 ? (
                  <p className="text-sm text-zinc-500">{t.noResults}</p>
                ) : (
                  <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
                    <table className="w-full min-w-max text-sm">
                      <thead className="bg-zinc-50 dark:bg-zinc-900">
                        <tr>
                          <th className="p-2 text-start">{t.dateColumn}</th>
                          <th className="p-2 text-end">{t.totalOrders}</th>
                          <th className="p-2 text-end">{t.totalGross}</th>
                          <th className="p-2 text-end">{t.totalNet}</th>
                          <th className="p-2 text-end">{t.wasteColumn}</th>
                          <th className="p-2 text-end">
                            {t.hospitalityColumn}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {byDay.map(([day, d]) => (
                          <tr
                            key={day}
                            className="border-t border-zinc-100 dark:border-zinc-800"
                          >
                            <td className="p-2">{day}</td>
                            <td className="p-2 text-end">{d.orders}</td>
                            <td className="p-2 text-end">
                              {d.gross.toFixed(2)}
                            </td>
                            <td className="p-2 text-end">
                              {d.net.toFixed(2)}
                            </td>
                            <td className="p-2 text-end">
                              {d.waste.toFixed(2)}
                            </td>
                            <td className="p-2 text-end">
                              {d.hospitality.toFixed(2)}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>

              <section>
                <h2 className="mb-2 text-lg font-semibold">
                  {locationName(locationId)} — {t.allSources}
                </h2>
                {bySource.length === 0 ? (
                  <p className="text-sm text-zinc-500">{t.noResults}</p>
                ) : (
                  <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
                    <table className="w-full min-w-max text-sm">
                      <thead className="bg-zinc-50 dark:bg-zinc-900">
                        <tr>
                          <th className="p-2 text-start">
                            {t.detectedSource}
                          </th>
                          <th className="p-2 text-end">{t.totalOrders}</th>
                          <th className="p-2 text-end">{t.totalGross}</th>
                          <th className="p-2 text-end">{t.totalNet}</th>
                        </tr>
                      </thead>
                      <tbody>
                        {bySource.map(([src, d]) => (
                          <tr
                            key={src}
                            className="border-t border-zinc-100 dark:border-zinc-800"
                          >
                            <td className="p-2">{src}</td>
                            <td className="p-2 text-end">{d.orders}</td>
                            <td className="p-2 text-end">
                              {d.gross.toFixed(2)}
                            </td>
                            <td className="p-2 text-end">
                              {d.net.toFixed(2)}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
            </>
          )}
        </>
      )}
    </div>
  );
}

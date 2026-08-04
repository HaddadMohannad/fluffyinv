import { useEffect, useMemo, useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import { downloadCsv } from "@/lib/exportCsv";
import type { Tables } from "@/lib/supabase/database.types";

function monthStart() {
  const d = new Date();
  d.setDate(1);
  return d.toISOString().slice(0, 10);
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

export function AccountantDashboardPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();

  const canView = profile?.role === "admin" || profile?.role === "accountant";

  const [dateFrom, setDateFrom] = useState(monthStart);
  const [dateTo, setDateTo] = useState(today);

  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [pendingInvoiceCount, setPendingInvoiceCount] = useState(0);
  const [todaysSales, setTodaysSales] = useState(0);
  const [invoicedByLocation, setInvoicedByLocation] = useState<
    Record<string, number>
  >({});
  const [purchasedByLocation, setPurchasedByLocation] = useState<
    Record<string, number>
  >({});
  const [exporting, setExporting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!canView) return;
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
  }, [canView]);

  useEffect(() => {
    if (!canView) return;
    supabase
      .from("supplier_invoices")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending")
      .then(({ count }) => setPendingInvoiceCount(count ?? 0));
    supabase
      .from("sales_orders")
      .select("gross")
      .eq("order_date", today())
      .then(({ data }) => {
        setTodaysSales((data ?? []).reduce((sum, r) => sum + r.gross, 0));
      });
  }, [canView]);

  useEffect(() => {
    if (!canView || !dateFrom || !dateTo) return;
    const toBound = `${dateTo}T23:59:59`;

    supabase
      .from("supplier_invoices")
      .select("location_id, amount")
      .eq("status", "approved")
      .gte("created_at", dateFrom)
      .lte("created_at", toBound)
      .then(({ data }) => {
        const map: Record<string, number> = {};
        for (const row of data ?? []) {
          map[row.location_id] = (map[row.location_id] ?? 0) + row.amount;
        }
        setInvoicedByLocation(map);
      });

    supabase
      .from("stock_ledger")
      .select("location_id, qty, unit_cost")
      .eq("movement", "purchase")
      .gte("created_at", dateFrom)
      .lte("created_at", toBound)
      .then(({ data }) => {
        const map: Record<string, number> = {};
        for (const row of data ?? []) {
          map[row.location_id] =
            (map[row.location_id] ?? 0) + row.qty * row.unit_cost;
        }
        setPurchasedByLocation(map);
      });
  }, [canView, dateFrom, dateTo]);

  const locationName = useMemo(() => {
    const map = new Map(
      locations.map((l) => [l.id, locale === "ar" ? l.name_ar : l.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [locations, locale]);

  const reconciliationRows = useMemo(() => {
    const locationIds = new Set([
      ...Object.keys(invoicedByLocation),
      ...Object.keys(purchasedByLocation),
    ]);
    return Array.from(locationIds).map((id) => {
      const invoiced = invoicedByLocation[id] ?? 0;
      const purchased = purchasedByLocation[id] ?? 0;
      return { locationId: id, invoiced, purchased, diff: purchased - invoiced };
    });
  }, [invoicedByLocation, purchasedByLocation]);

  if (!canView) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleExportAll() {
    setExporting(true);
    setError(null);
    const toBound = `${dateTo}T23:59:59`;
    const suffix = `${dateFrom}_${dateTo}`;

    try {
      const [
        { data: products },
        { data: suppliers },
        { data: sales },
        { data: stock },
        { data: invoices },
        { data: hospitality },
        { data: waste },
      ] = await Promise.all([
        supabase.from("products").select("*"),
        supabase.from("suppliers").select("*"),
        supabase
          .from("sales_orders")
          .select("order_date, source, location_id, gross, commission, net")
          .gte("order_date", dateFrom)
          .lte("order_date", dateTo),
        supabase.from("v_current_stock").select("location_id, product_id, qty"),
        supabase
          .from("supplier_invoices")
          .select("supplier_id, location_id, invoice_no, amount, status, due_date")
          .gte("created_at", dateFrom)
          .lte("created_at", toBound),
        supabase
          .from("hospitality_records")
          .select("location_id, product_id, qty, h_type, value, created_at")
          .gte("created_at", dateFrom)
          .lte("created_at", toBound),
        supabase
          .from("waste_records")
          .select("location_id, product_id, qty, reason, value_lost, created_at")
          .gte("created_at", dateFrom)
          .lte("created_at", toBound),
      ]);

      const productName = new Map(
        (products ?? []).map((p) => [p.id, p.name_en])
      );
      const supplierName = new Map((suppliers ?? []).map((s) => [s.id, s.name]));
      const avgCost = new Map((products ?? []).map((p) => [p.id, p.avg_cost]));

      downloadCsv(
        `fluffy-export-sales-${suffix}.csv`,
        ["Date", "Source", "Branch", "Gross", "Commission", "Net"],
        (sales ?? []).map((r) => [
          r.order_date,
          r.source,
          locationName(r.location_id),
          r.gross,
          r.commission,
          r.net,
        ])
      );

      downloadCsv(
        `fluffy-export-stock-${suffix}.csv`,
        ["Branch", "Product", "Quantity", "Unit Cost", "Total Value"],
        (stock ?? [])
          .filter((r) => r.location_id && r.product_id && r.qty !== null)
          .map((r) => {
            const cost = avgCost.get(r.product_id as string) ?? 0;
            return [
              locationName(r.location_id as string),
              productName.get(r.product_id as string) ?? r.product_id!,
              r.qty as number,
              cost,
              (r.qty as number) * cost,
            ];
          })
      );

      downloadCsv(
        `fluffy-export-invoices-${suffix}.csv`,
        ["Supplier", "Invoice #", "Branch", "Amount", "Status", "Due Date"],
        (invoices ?? []).map((r) => [
          supplierName.get(r.supplier_id) ?? r.supplier_id,
          r.invoice_no,
          locationName(r.location_id),
          r.amount,
          r.status,
          r.due_date ?? "",
        ])
      );

      downloadCsv(
        `fluffy-export-hospitality-${suffix}.csv`,
        ["Branch", "Product", "Quantity", "Type", "Value", "Date"],
        (hospitality ?? []).map((r) => [
          locationName(r.location_id),
          productName.get(r.product_id) ?? r.product_id,
          r.qty,
          r.h_type,
          r.value,
          r.created_at.slice(0, 10),
        ])
      );

      downloadCsv(
        `fluffy-export-waste-${suffix}.csv`,
        ["Branch", "Product", "Quantity", "Reason", "Value Lost", "Date"],
        (waste ?? []).map((r) => [
          locationName(r.location_id),
          productName.get(r.product_id) ?? r.product_id,
          r.qty,
          r.reason ?? "",
          r.value_lost,
          r.created_at.slice(0, 10),
        ])
      );
    } catch (err) {
      console.error("Comprehensive export failed:", err);
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setExporting(false);
    }
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.accountantDashboardTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.pendingInvoicesLabel}
          </p>
          <p className="text-xl font-semibold text-amber-600">
            {pendingInvoiceCount}
          </p>
        </div>
        <div className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.todaysSalesLabel}
          </p>
          <p className="text-xl font-semibold">{todaysSales.toFixed(2)} JOD</p>
        </div>
      </div>

      <div className="flex flex-wrap items-end gap-3">
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
        <button
          type="button"
          disabled={exporting}
          onClick={handleExportAll}
          className="bg-fluffy-orange h-11 rounded-md px-4 text-sm font-medium text-white disabled:opacity-60"
        >
          {exporting ? t.submitting : t.exportAllButton}
        </button>
      </div>

      <section>
        <h2 className="mb-2 text-lg font-semibold">{t.reconciliationTitle}</h2>
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.location}</th>
                <th className="p-2 text-end">{t.invoicedColumn}</th>
                <th className="p-2 text-end">{t.purchasedColumn}</th>
                <th className="p-2 text-end">{t.differenceColumn}</th>
              </tr>
            </thead>
            <tbody>
              {reconciliationRows.map((row) => (
                <tr
                  key={row.locationId}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="p-2">{locationName(row.locationId)}</td>
                  <td className="p-2 text-end">{row.invoiced.toFixed(2)}</td>
                  <td className="p-2 text-end">{row.purchased.toFixed(2)}</td>
                  <td
                    className={`p-2 text-end ${row.diff !== 0 ? "text-amber-600" : ""}`}
                  >
                    {row.diff.toFixed(2)}
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

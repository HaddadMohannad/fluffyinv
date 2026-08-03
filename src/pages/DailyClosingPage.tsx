import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

function today() {
  return new Date().toISOString().slice(0, 10);
}

type ReportRow = {
  product_id: string;
  opening_qty: number;
  received_qty: number;
  sold_qty: number;
  waste_qty: number;
  hospitality_qty: number;
  expected_closing_qty: number;
  current_qty: number;
};

export function DailyClosingPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations, locationId: headerLocationId } = useActiveLocation();

  const canView =
    profile?.role === "admin" ||
    profile?.role === "accountant" ||
    profile?.role === "branch_manager";
  const canClose = profile?.role === "admin" || profile?.role === "accountant";
  const canReopen = profile?.role === "admin";
  const isLocationLocked = profile?.role === "branch_manager";

  const [locationId, setLocationId] = useState("");
  const [closeDate, setCloseDate] = useState(today);
  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [report, setReport] = useState<ReportRow[]>([]);
  const [closeRecord, setCloseRecord] = useState<Tables<"day_closes"> | null>(
    null
  );
  const [reopenReason, setReopenReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canView) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canView]);

  useEffect(() => {
    if (isLocationLocked) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- lock to the branch_manager's own location
      setLocationId(profile?.location_id ?? "");
      return;
    }
    if (!locationId && headerLocationId) {
      setLocationId(headerLocationId);
    }
  }, [isLocationLocked, profile?.location_id, headerLocationId, locationId]);

  useEffect(() => {
    if (!locationId || !closeDate) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when inputs are unset
      setReport([]);
      setCloseRecord(null);
      return;
    }
    setError(null);
    supabase
      .rpc("get_daily_closing_report", {
        p_location_id: locationId,
        p_close_date: closeDate,
      })
      .then(({ data, error: rpcError }) => {
        if (rpcError) {
          console.error("Load daily closing report failed:", rpcError);
          setError(rpcError.message);
          return;
        }
        setReport(data ?? []);
      });
    supabase
      .from("day_closes")
      .select("*")
      .eq("location_id", locationId)
      .eq("close_date", closeDate)
      .maybeSingle()
      .then(({ data }) => setCloseRecord(data));
  }, [locationId, closeDate, refreshKey]);

  const productName = useMemo(() => {
    const map = new Map(
      products.map((p) => [p.id, locale === "ar" ? p.name_ar : p.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [products, locale]);

  const visibleRows = useMemo(
    () =>
      report.filter(
        (r) =>
          r.opening_qty !== 0 ||
          r.received_qty !== 0 ||
          r.sold_qty !== 0 ||
          r.waste_qty !== 0 ||
          r.hospitality_qty !== 0 ||
          r.current_qty !== 0
      ),
    [report]
  );

  if (!canView) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleClose() {
    setBusy(true);
    setError(null);
    setMessage(null);
    const { error: rpcError } = await supabase.rpc("close_day", {
      p_location_id: locationId,
      p_close_date: closeDate,
    });
    setBusy(false);
    if (rpcError) {
      console.error("Close day failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setMessage(t.dayClosed);
    setRefreshKey((k) => k + 1);
  }

  async function handleReopen(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    if (!reopenReason.trim()) {
      setError(t.reopenReasonRequired);
      return;
    }
    setBusy(true);
    const { error: rpcError } = await supabase.rpc("reopen_day", {
      p_location_id: locationId,
      p_close_date: closeDate,
      p_reason: reopenReason.trim(),
    });
    setBusy(false);
    if (rpcError) {
      console.error("Reopen day failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setMessage(t.dayReopened);
    setReopenReason("");
    setRefreshKey((k) => k + 1);
  }

  const isClosed = Boolean(closeRecord) && !closeRecord?.reopened_at;
  const isReopened = Boolean(closeRecord?.reopened_at);

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.dailyClosingTitle}
      </h1>

      <div className="flex max-w-md flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.location}
          <select
            value={locationId}
            onChange={(e) => setLocationId(e.target.value)}
            disabled={isLocationLocked}
            className="h-11 rounded-md border border-zinc-300 px-3 disabled:opacity-60 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.location}
            </option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {locale === "ar" ? l.name_ar : l.name_en}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.closeDateLabel}
          <input
            type="date"
            value={closeDate}
            onChange={(e) => setCloseDate(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      {locationId && closeDate && (
        <>
          <div className="flex items-center gap-3 text-sm">
            <span className="font-medium">
              {isReopened
                ? t.statusReopenedLabel
                : isClosed
                  ? t.statusClosedLabel
                  : t.statusOpenLabel}
            </span>
            {closeRecord?.closed_at && (
              <span className="text-zinc-600 dark:text-zinc-400">
                {t.closedAtLabel}: {new Date(closeRecord.closed_at).toLocaleString()}
              </span>
            )}
            {closeRecord?.reopened_at && (
              <span className="text-zinc-600 dark:text-zinc-400">
                {t.reopenedAtLabel}:{" "}
                {new Date(closeRecord.reopened_at).toLocaleString()} (
                {closeRecord.reopen_reason})
              </span>
            )}
          </div>

          {canClose && !closeRecord && (
            <button
              type="button"
              disabled={busy}
              onClick={handleClose}
              className="bg-fluffy-orange h-11 max-w-md rounded-md text-base font-medium text-white disabled:opacity-60"
            >
              {busy ? t.closingDay : t.closeDayButton}
            </button>
          )}

          {canReopen && isClosed && (
            <form
              onSubmit={handleReopen}
              className="flex max-w-md flex-col gap-2"
            >
              <label className="flex flex-col gap-1 text-sm">
                {t.reopenReasonLabel}
                <input
                  type="text"
                  value={reopenReason}
                  onChange={(e) => setReopenReason(e.target.value)}
                  className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
                />
              </label>
              <button
                type="submit"
                disabled={busy}
                className="h-11 rounded-md border border-zinc-300 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
              >
                {busy ? t.reopeningDay : t.reopenDayButton}
              </button>
            </form>
          )}

          <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.product}</th>
                  <th className="p-2 text-end">{t.openingQtyColumn}</th>
                  <th className="p-2 text-end">{t.receivedQtyColumn}</th>
                  <th className="p-2 text-end">{t.soldQtyColumn}</th>
                  <th className="p-2 text-end">{t.wasteQtyColumn}</th>
                  <th className="p-2 text-end">{t.hospitalityQtyColumn}</th>
                  <th className="p-2 text-end">{t.expectedClosingColumn}</th>
                  <th className="p-2 text-end">{t.currentQtyColumn}</th>
                </tr>
              </thead>
              <tbody>
                {visibleRows.map((row) => (
                  <tr
                    key={row.product_id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{productName(row.product_id)}</td>
                    <td className="p-2 text-end">{row.opening_qty}</td>
                    <td className="p-2 text-end">{row.received_qty}</td>
                    <td className="p-2 text-end">{row.sold_qty}</td>
                    <td className="p-2 text-end">{row.waste_qty}</td>
                    <td className="p-2 text-end">{row.hospitality_qty}</td>
                    <td className="p-2 text-end">{row.expected_closing_qty}</td>
                    <td className="p-2 text-end">{row.current_qty}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}

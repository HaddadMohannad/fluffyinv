import { useEffect, useMemo, useState } from "react";
import { CalendarDays, Trash2, Wallet } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { StatCard } from "@/components/StatCard";
import { AddWasteModal } from "@/components/quick-actions/AddWasteModal";

function startOfDayIso(daysAgo: number) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - daysAgo);
  return d.toISOString();
}

export function WastePage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locationId } = useActiveLocation();

  const canWrite =
    profile?.role === "admin" || profile?.role === "branch_manager";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [reasons, setReasons] = useState<Tables<"lookup_values">[]>([]);
  const [recent, setRecent] = useState<Tables<"waste_records">[]>([]);
  const [wasteToday, setWasteToday] = useState(0);
  const [wasteThisWeek, setWasteThisWeek] = useState(0);
  const [wasteAllTime, setWasteAllTime] = useState(0);
  const [refreshKey, setRefreshKey] = useState(0);
  const [showAddModal, setShowAddModal] = useState(false);

  const reasonLabel = useMemo(() => {
    const map = new Map(
      reasons.map((r) => [r.code, locale === "ar" ? r.name_ar : r.name_en])
    );
    return (code: string) => map.get(code) ?? code;
  }, [reasons, locale]);

  const productName = useMemo(() => {
    const map = new Map(
      products.map((p) => [p.id, locale === "ar" ? p.name_ar : p.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [products, locale]);

  useEffect(() => {
    if (!canWrite) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
    supabase
      .from("lookup_values")
      .select("*")
      .eq("list_key", "waste_reason")
      .eq("active", true)
      .order("sort_order")
      .then(({ data }) => setReasons(data ?? []));
  }, [canWrite]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when location is unset
      setRecent([]);
      setWasteToday(0);
      setWasteThisWeek(0);
      setWasteAllTime(0);
      return;
    }
    supabase
      .from("waste_records")
      .select("*")
      .eq("location_id", locationId)
      .order("created_at", { ascending: false })
      .limit(20)
      .then(({ data }) => setRecent(data ?? []));

    supabase
      .from("waste_records")
      .select("value_lost")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(0))
      .then(({ data }) => {
        setWasteToday((data ?? []).reduce((sum, r) => sum + r.value_lost, 0));
      });
    supabase
      .from("waste_records")
      .select("value_lost")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(6))
      .then(({ data }) => {
        setWasteThisWeek(
          (data ?? []).reduce((sum, r) => sum + r.value_lost, 0)
        );
      });
    supabase
      .from("waste_records")
      .select("value_lost")
      .eq("location_id", locationId)
      .then(({ data }) => {
        setWasteAllTime((data ?? []).reduce((sum, r) => sum + r.value_lost, 0));
      });
  }, [locationId, refreshKey]);

  if (!canWrite) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function handleSaved() {
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.wasteTitle}
        </h1>
        <button
          type="button"
          disabled={!locationId}
          onClick={() => setShowAddModal(true)}
          className="h-9 rounded-md bg-red-600 px-4 text-sm font-medium text-white disabled:opacity-60"
        >
          {t.addWasteAction}
        </button>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <StatCard
          label={t.todaysWasteLabel}
          value={`${wasteToday.toFixed(2)} JOD`}
          icon={Trash2}
        />
        <StatCard
          label={t.totalWasteWeekLabel}
          value={`${wasteThisWeek.toFixed(2)} JOD`}
          icon={CalendarDays}
        />
        <StatCard
          label={t.totalValueLostLabel}
          value={`${wasteAllTime.toFixed(2)} JOD`}
          icon={Wallet}
        />
      </div>

      {locationId && (
        <section>
          <h2 className="mb-2 text-lg font-semibold">{t.recentEntriesTitle}</h2>
          <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.product}</th>
                  <th className="p-2 text-end">{t.quantity}</th>
                  <th className="p-2 text-start">{t.wasteReasonLabel}</th>
                  <th className="p-2 text-end">{t.valueLostLabel}</th>
                </tr>
              </thead>
              <tbody>
                {recent.map((entry) => (
                  <tr
                    key={entry.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{productName(entry.product_id)}</td>
                    <td className="p-2 text-end">{entry.qty}</td>
                    <td className="p-2">{reasonLabel(entry.reason ?? "")}</td>
                    <td className="p-2 text-end">{entry.value_lost}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {showAddModal && (
        <AddWasteModal
          locationId={locationId}
          onClose={() => setShowAddModal(false)}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}

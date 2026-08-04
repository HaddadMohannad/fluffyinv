import { useEffect, useState, type FormEvent } from "react";
import { CalendarDays, Heart, Wallet } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import { StatCard } from "@/components/StatCard";
import { AddHospitalityModal } from "@/components/quick-actions/AddHospitalityModal";

function startOfDayIso(daysAgo: number) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - daysAgo);
  return d.toISOString();
}

export function HospitalityPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations, locationId } = useActiveLocation();

  const canWrite =
    profile?.role === "admin" || profile?.role === "branch_manager";
  const isAdmin = profile?.role === "admin";

  const [usageToday, setUsageToday] = useState(0);
  const [usageThisWeek, setUsageThisWeek] = useState(0);
  const [usageAllTime, setUsageAllTime] = useState(0);
  const [monthUsage, setMonthUsage] = useState<number | null>(null);
  const [monthLimit, setMonthLimit] = useState<number | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [showAddModal, setShowAddModal] = useState(false);

  const [limitLocationId, setLimitLocationId] = useState("");
  const [limitValue, setLimitValue] = useState("");
  const [savingLimit, setSavingLimit] = useState(false);
  const [limitMessage, setLimitMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when location is unset
      setUsageToday(0);
      setUsageThisWeek(0);
      setUsageAllTime(0);
      setMonthUsage(null);
      setMonthLimit(null);
      return;
    }

    supabase
      .from("hospitality_records")
      .select("value")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(0))
      .then(({ data }) => {
        setUsageToday((data ?? []).reduce((sum, r) => sum + (r.value ?? 0), 0));
      });
    supabase
      .from("hospitality_records")
      .select("value")
      .eq("location_id", locationId)
      .gte("created_at", startOfDayIso(6))
      .then(({ data }) => {
        setUsageThisWeek(
          (data ?? []).reduce((sum, r) => sum + (r.value ?? 0), 0)
        );
      });
    supabase
      .from("hospitality_records")
      .select("value")
      .eq("location_id", locationId)
      .then(({ data }) => {
        setUsageAllTime(
          (data ?? []).reduce((sum, r) => sum + (r.value ?? 0), 0)
        );
      });

    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);
    const monthStr = monthStart.toISOString().slice(0, 10);

    supabase
      .from("hospitality_records")
      .select("value")
      .eq("location_id", locationId)
      .gte("created_at", monthStart.toISOString())
      .then(({ data }) => {
        const total = (data ?? []).reduce((sum, r) => sum + (r.value ?? 0), 0);
        setMonthUsage(total);
      });
    supabase
      .from("hospitality_limits")
      .select("limit_value")
      .eq("location_id", locationId)
      .eq("month", monthStr)
      .maybeSingle()
      .then(({ data }) => setMonthLimit(data?.limit_value ?? null));
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

  async function handleSaveLimit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLimitMessage(null);
    if (!limitLocationId) return;
    const value = Number(limitValue);
    if (!Number.isFinite(value) || value < 0) {
      setLimitMessage(t.invalidQuantity);
      return;
    }
    setSavingLimit(true);
    const monthStart = new Date();
    monthStart.setDate(1);
    const monthStr = monthStart.toISOString().slice(0, 10);
    const { error: upsertError } = await supabase
      .from("hospitality_limits")
      .upsert(
        { location_id: limitLocationId, month: monthStr, limit_value: value },
        { onConflict: "location_id,month" }
      );
    setSavingLimit(false);
    if (upsertError) {
      console.error("Save limit failed:", upsertError);
      setLimitMessage(upsertError.message);
      return;
    }
    setLimitMessage(t.limitSaved);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.hospitalityTitle}
        </h1>
        <button
          type="button"
          disabled={!locationId}
          onClick={() => setShowAddModal(true)}
          className="bg-fluffy-orange h-9 rounded-md px-4 text-sm font-medium text-white disabled:opacity-60"
        >
          {t.addHospitalityAction}
        </button>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <StatCard
          label={t.todaysUsageLabel}
          value={`${usageToday.toFixed(2)} JOD`}
          icon={Heart}
        />
        <StatCard
          label={t.totalUsageWeekLabel}
          value={`${usageThisWeek.toFixed(2)} JOD`}
          icon={CalendarDays}
        />
        <StatCard
          label={t.totalValueLabel}
          value={`${usageAllTime.toFixed(2)} JOD`}
          icon={Wallet}
        />
      </div>

      {locationId && monthLimit !== null && monthUsage !== null && (
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          {t.monthUsageLabel}: {monthUsage.toFixed(3)} / {monthLimit.toFixed(3)}{" "}
          JOD ({((monthUsage / monthLimit) * 100).toFixed(1)}%)
        </p>
      )}

      {isAdmin && (
        <section className="max-w-md rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
          <h2 className="mb-2 text-lg font-semibold">
            {t.setMonthlyLimitTitle}
          </h2>
          <form onSubmit={handleSaveLimit} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.location}
              <select
                value={limitLocationId}
                onChange={(e) => setLimitLocationId(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
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
              {t.monthlyLimitValueLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={limitValue}
                onChange={(e) => setLimitValue(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            {limitMessage && (
              <p className="text-sm text-green-600">{limitMessage}</p>
            )}
            <button
              type="submit"
              disabled={savingLimit || !limitLocationId}
              className="h-11 rounded-md border border-zinc-300 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
            >
              {savingLimit ? t.savingLimit : t.saveLimit}
            </button>
          </form>
        </section>
      )}

      {showAddModal && (
        <AddHospitalityModal
          locationId={locationId}
          onClose={() => setShowAddModal(false)}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}

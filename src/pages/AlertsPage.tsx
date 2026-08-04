import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type Alert = {
  alert_type: string;
  location_id: string;
  metric_value: number;
  threshold_value: number;
  detail: Record<string, unknown> | null;
};

export function AlertsPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations } = useActiveLocation();

  const canView = profile?.role === "admin" || profile?.role === "accountant";
  const canManageSettings = profile?.role === "admin";

  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [wasteThreshold, setWasteThreshold] = useState("");
  const [stocktakeThreshold, setStocktakeThreshold] = useState("");
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canView) return;
    supabase
      .rpc("get_smart_alerts")
      .then(({ data, error: rpcError }) => {
        if (rpcError) {
          console.error("Load smart alerts failed:", rpcError);
          setError(rpcError.message);
          return;
        }
        setAlerts((data as Alert[]) ?? []);
      });
    supabase
      .from("products")
      .select("*")
      .then(({ data }) => setProducts(data ?? []));
    supabase
      .from("alert_settings")
      .select("*")
      .eq("id", true)
      .single()
      .then(({ data }) => {
        if (data) {
          setWasteThreshold(String(data.waste_alert_threshold_jod));
          setStocktakeThreshold(String(data.stocktake_alert_threshold_jod));
        }
      });
  }, [canView, refreshKey]);

  const locationName = useMemo(() => {
    const map = new Map(
      locations.map((l) => [l.id, locale === "ar" ? l.name_ar : l.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [locations, locale]);

  const productName = useMemo(() => {
    const map = new Map(
      products.map((p) => [p.id, locale === "ar" ? p.name_ar : p.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [products, locale]);

  const alertLabel = (type: string) => {
    if (type === "hospitality") return t.alertHospitalityLabel;
    if (type === "waste") return t.alertWasteLabel;
    if (type === "stocktake") return t.alertStocktakeLabel;
    return type;
  };

  const alertColor = (type: string) => {
    if (type === "hospitality") return "border-amber-400 bg-amber-50 dark:border-amber-700 dark:bg-amber-950";
    if (type === "waste") return "border-red-400 bg-red-50 dark:border-red-700 dark:bg-red-950";
    return "border-orange-400 bg-orange-50 dark:border-orange-700 dark:bg-orange-950";
  };

  function alertDetail(alert: Alert) {
    if (alert.alert_type === "hospitality") {
      const pct = (alert.detail?.usage_pct as number | undefined) ?? 0;
      return `${pct}% — ${alert.metric_value.toFixed(2)} / ${alert.threshold_value.toFixed(2)} JOD`;
    }
    if (alert.alert_type === "waste") {
      return `${alert.metric_value.toFixed(2)} JOD (${t.wasteThresholdLabel}: ${alert.threshold_value.toFixed(2)} JOD)`;
    }
    const productId = alert.detail?.product_id as string | undefined;
    return `${productId ? productName(productId) : ""} — ${alert.metric_value.toFixed(2)} JOD (${alert.threshold_value.toFixed(2)} JOD)`;
  }

  if (!canView) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleSaveThresholds(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    const wasteNum = Number(wasteThreshold);
    const stocktakeNum = Number(stocktakeThreshold);
    if (!Number.isFinite(wasteNum) || wasteNum < 0 || !Number.isFinite(stocktakeNum) || stocktakeNum < 0) {
      setError(t.invalidQuantity);
      return;
    }

    setSaving(true);
    const { error: rpcError } = await supabase.rpc("save_alert_settings", {
      p_waste_threshold_jod: wasteNum,
      p_stocktake_threshold_jod: stocktakeNum,
    });
    setSaving(false);

    if (rpcError) {
      console.error("Save alert settings failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    setMessage(t.thresholdsSaved);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.alertsTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      {alerts.length === 0 ? (
        <p className="text-sm text-zinc-600 dark:text-zinc-400">{t.noAlerts}</p>
      ) : (
        <div className="flex flex-col gap-3">
          {alerts.map((alert, i) => (
            <div
              key={i}
              className={`flex flex-col gap-1 rounded-md border p-3 text-sm ${alertColor(alert.alert_type)}`}
            >
              <div className="flex items-center justify-between">
                <span className="font-medium">{alertLabel(alert.alert_type)}</span>
                <span className="text-zinc-600 dark:text-zinc-400">
                  {locationName(alert.location_id)}
                </span>
              </div>
              <p>{alertDetail(alert)}</p>
            </div>
          ))}
        </div>
      )}

      {canManageSettings && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">{t.alertSettingsTitle}</h2>
          <form onSubmit={handleSaveThresholds} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.wasteThresholdLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={wasteThreshold}
                onChange={(e) => setWasteThreshold(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.stocktakeThresholdLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={stocktakeThreshold}
                onChange={(e) => setStocktakeThreshold(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <button
              type="submit"
              disabled={saving}
              className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
            >
              {saving ? t.savingThresholds : t.saveThresholds}
            </button>
          </form>
        </section>
      )}
    </div>
  );
}

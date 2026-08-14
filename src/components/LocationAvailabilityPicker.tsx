import { useEffect, useState } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

export function LocationAvailabilityPicker({
  productId,
}: {
  productId: string;
}) {
  const { t } = useLocale();

  const [branches, setBranches] = useState<Tables<"locations">[]>([]);
  const [restricted, setRestricted] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    supabase
      .from("locations")
      .select("*")
      .eq("type", "branch")
      .order("name_en")
      .then(({ data }) => setBranches(data ?? []));
  }, []);

  useEffect(() => {
    supabase
      .from("product_locations")
      .select("location_id")
      .eq("product_id", productId)
      .then(({ data }) => {
        setRestricted(new Set((data ?? []).map((r) => r.location_id)));
      });
  }, [productId, refreshKey]);

  const isRestricted = restricted.size > 0;

  async function toggle(locationId: string, available: boolean) {
    setError(null);

    if (!isRestricted && !available) {
      // Currently unrestricted (no rows = every branch). Unchecking one
      // branch means switching into restricted mode: insert rows for
      // every branch except this one.
      const rows = branches
        .filter((b) => b.id !== locationId)
        .map((b) => ({ product_id: productId, location_id: b.id }));
      const { error: insertError } = await supabase
        .from("product_locations")
        .insert(rows);
      if (insertError) {
        console.error("Restrict product locations failed:", insertError);
        setError(insertError.message);
        return;
      }
      setRefreshKey((k) => k + 1);
      return;
    }

    if (isRestricted && available && restricted.size === branches.length - 1) {
      // Checking the last missing branch brings it back to "every branch"
      // -- collapse back to zero rows rather than one row per branch.
      const { error: deleteError } = await supabase
        .from("product_locations")
        .delete()
        .eq("product_id", productId);
      if (deleteError) {
        console.error("Clear product locations failed:", deleteError);
        setError(deleteError.message);
        return;
      }
      setRefreshKey((k) => k + 1);
      return;
    }

    const { error: toggleError } = available
      ? await supabase
          .from("product_locations")
          .insert({ product_id: productId, location_id: locationId })
      : await supabase
          .from("product_locations")
          .delete()
          .eq("product_id", productId)
          .eq("location_id", locationId);
    if (toggleError) {
      console.error("Toggle product location failed:", toggleError);
      setError(toggleError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-col gap-2">
      {error && <p className="text-sm text-red-600">{error}</p>}
      <p className="text-xs text-zinc-500 dark:text-zinc-400">
        {isRestricted ? t.availableSelectedBranches : t.availableAllBranches}
      </p>
      <div className="flex flex-wrap gap-3">
        {branches.map((b) => (
          <label key={b.id} className="flex items-center gap-1.5 text-sm">
            <input
              type="checkbox"
              checked={!isRestricted || restricted.has(b.id)}
              onChange={() =>
                toggle(b.id, !(!isRestricted || restricted.has(b.id)))
              }
            />
            {b.name_ar || b.name_en}
          </label>
        ))}
      </div>
    </div>
  );
}

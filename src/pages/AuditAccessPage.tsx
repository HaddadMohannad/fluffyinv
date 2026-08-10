import { useEffect, useMemo, useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

export function AuditAccessPage() {
  const { profile } = useAuth();
  const { t } = useLocale();

  const canManage = profile?.role === "admin";

  const [managers, setManagers] = useState<Tables<"profiles">[]>([]);
  const [managerId, setManagerId] = useState("");
  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [grants, setGrants] = useState<Tables<"audit_location_grants">[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canManage) return;
    supabase
      .from("profiles")
      .select("*")
      .in("role", ["branch_manager", "inspector"])
      .order("full_name")
      .then(({ data }) => {
        const rows = data ?? [];
        setManagers(rows);
        setManagerId(
          (current) => current || (rows.length > 0 ? rows[0].id : "")
        );
      });
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
  }, [canManage]);

  useEffect(() => {
    if (!managerId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived grants when manager is unset
      setGrants([]);
      return;
    }
    supabase
      .from("audit_location_grants")
      .select("*")
      .eq("profile_id", managerId)
      .then(({ data }) => setGrants(data ?? []));
  }, [managerId, refreshKey]);

  const selectedManager = useMemo(
    () => managers.find((m) => m.id === managerId),
    [managers, managerId]
  );

  const grantedLocationIds = useMemo(
    () => new Set(grants.map((g) => g.location_id)),
    [grants]
  );

  if (!canManage) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function toggleGrant(locationId: string, granted: boolean) {
    setError(null);
    if (granted) {
      const { error: deleteError } = await supabase
        .from("audit_location_grants")
        .delete()
        .eq("profile_id", managerId)
        .eq("location_id", locationId);
      if (deleteError) {
        console.error("Remove audit location grant failed:", deleteError);
        setError(deleteError.message);
        return;
      }
    } else {
      const { error: insertError } = await supabase
        .from("audit_location_grants")
        .insert({ profile_id: managerId, location_id: locationId });
      if (insertError) {
        console.error("Add audit location grant failed:", insertError);
        setError(insertError.message);
        return;
      }
    }
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.auditAccessTitle}
      </h1>

      {managers.length === 0 ? (
        <p className="text-sm text-zinc-500 dark:text-zinc-400">
          {t.noBranchManagersYet}
        </p>
      ) : (
        <>
          <label className="flex max-w-sm flex-col gap-1 text-sm">
            {t.managerLabel}
            <select
              value={managerId}
              onChange={(e) => setManagerId(e.target.value)}
              className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
            >
              {managers.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.full_name}
                </option>
              ))}
            </select>
          </label>

          {error && <p className="text-sm text-red-600">{error}</p>}

          <div className="max-w-md overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.branchTypeLabel}</th>
                  <th className="p-2 text-center">{t.auditAccessGranted}</th>
                </tr>
              </thead>
              <tbody>
                {locations.map((loc) => {
                  const isOwn = selectedManager?.location_id === loc.id;
                  const granted = isOwn || grantedLocationIds.has(loc.id);
                  return (
                    <tr
                      key={loc.id}
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="p-2">
                        {loc.name_ar || loc.name_en}
                        {isOwn && (
                          <span className="ms-2 text-xs text-zinc-500">
                            ({t.ownBranchLabel})
                          </span>
                        )}
                      </td>
                      <td className="p-2 text-center">
                        <input
                          type="checkbox"
                          checked={granted}
                          disabled={isOwn}
                          onChange={() => toggleGrant(loc.id, granted)}
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}

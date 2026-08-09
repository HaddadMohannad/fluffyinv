import { useEffect, useMemo, useState } from "react";
import { Pill } from "@/components/Pill";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { NAV_ITEMS } from "@/lib/navigation";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type Role = Tables<"profiles">["role"];

const ROLES: Role[] = [
  "admin",
  "branch_manager",
  "warehouse_staff",
  "accountant",
];

const ROLE_LABEL_KEY: Record<
  Role,
  "roleAdmin" | "roleBranchManager" | "roleWarehouseStaff" | "roleAccountant"
> = {
  admin: "roleAdmin",
  branch_manager: "roleBranchManager",
  warehouse_staff: "roleWarehouseStaff",
  accountant: "roleAccountant",
};

export function UsersPage() {
  const { profile: myProfile } = useAuth();
  const { t, locale } = useLocale();
  const canManage = myProfile?.role === "admin";

  const [requests, setRequests] = useState<Tables<"signup_requests">[]>([]);
  const [users, setUsers] = useState<Tables<"profiles">[]>([]);
  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [grants, setGrants] = useState<Tables<"audit_location_grants">[]>([]);
  const [activity, setActivity] = useState<Tables<"v_user_activity_log">[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const [requestRole, setRequestRole] = useState<Record<string, Role>>({});
  const [requestLocation, setRequestLocation] = useState<
    Record<string, string>
  >({});

  useEffect(() => {
    if (!canManage) return;
    supabase
      .from("signup_requests")
      .select("*")
      .eq("status", "pending")
      .order("requested_at")
      .then(({ data }) => setRequests(data ?? []));
    supabase
      .from("profiles")
      .select("*")
      .order("full_name")
      .then(({ data }) => setUsers(data ?? []));
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
  }, [canManage, refreshKey]);

  useEffect(() => {
    if (!selectedId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when selection is cleared
      setGrants([]);
      setActivity([]);
      return;
    }
    supabase
      .from("audit_location_grants")
      .select("*")
      .eq("profile_id", selectedId)
      .then(({ data }) => setGrants(data ?? []));
    supabase
      .from("v_user_activity_log")
      .select("*")
      .eq("actor_id", selectedId)
      .order("created_at", { ascending: false })
      .limit(50)
      .then(({ data }) => setActivity(data ?? []));
  }, [selectedId, refreshKey]);

  const selectedUser = useMemo(
    () => users.find((u) => u.id === selectedId) ?? null,
    [users, selectedId]
  );

  const visibleModules = useMemo(() => {
    if (!selectedUser) return [];
    return NAV_ITEMS.filter(
      (item) => !item.roles || item.roles.includes(selectedUser.role)
    ).map((item) => t[item.labelKey]);
  }, [selectedUser, t]);

  const grantedLocations = useMemo(
    () =>
      locations.filter((loc) => grants.some((g) => g.location_id === loc.id)),
    [locations, grants]
  );

  if (!canManage) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function locationName(loc: Tables<"locations">) {
    return locale === "ar" ? loc.name_ar || loc.name_en : loc.name_en;
  }

  async function handleApprove(requestId: string) {
    setError(null);
    setMessage(null);
    const role = requestRole[requestId] ?? "branch_manager";
    const locationId = requestLocation[requestId] || null;
    const { error: rpcError } = await supabase.rpc("approve_signup_request", {
      p_request_id: requestId,
      p_role: role,
      p_location_id: locationId ?? undefined,
    });
    if (rpcError) {
      console.error("Approve signup request failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setMessage(t.changesSaved);
    setRefreshKey((k) => k + 1);
  }

  async function handleReject(requestId: string) {
    setError(null);
    setMessage(null);
    const { error: rpcError } = await supabase.rpc("reject_signup_request", {
      p_request_id: requestId,
    });
    if (rpcError) {
      console.error("Reject signup request failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  async function updateSelectedUser(patch: Partial<Tables<"profiles">>) {
    if (!selectedUser) return;
    setError(null);
    setMessage(null);
    const { error: updateError } = await supabase
      .from("profiles")
      .update(patch)
      .eq("id", selectedUser.id);
    if (updateError) {
      console.error("Update user failed:", updateError);
      setError(updateError.message);
      return;
    }
    setMessage(t.changesSaved);
    setRefreshKey((k) => k + 1);
  }

  async function toggleGrant(locationId: string, granted: boolean) {
    if (!selectedUser) return;
    setError(null);
    if (granted) {
      const { error: deleteError } = await supabase
        .from("audit_location_grants")
        .delete()
        .eq("profile_id", selectedUser.id)
        .eq("location_id", locationId);
      if (deleteError) {
        setError(deleteError.message);
        return;
      }
    } else {
      const { error: insertError } = await supabase
        .from("audit_location_grants")
        .insert({ profile_id: selectedUser.id, location_id: locationId });
      if (insertError) {
        setError(insertError.message);
        return;
      }
    }
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.usersTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t.signupRequestsTitle}</h2>
        {requests.length === 0 ? (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">
            {t.noSignupRequests}
          </p>
        ) : (
          <div className="flex flex-col gap-3">
            {requests.map((req) => (
              <div
                key={req.id}
                className="flex flex-wrap items-center gap-3 rounded-md border border-zinc-200 p-3 text-sm dark:border-zinc-800"
              >
                <div className="min-w-[10rem] flex-1">
                  <p className="font-medium">{req.full_name || req.email}</p>
                  <p className="text-xs text-zinc-500 dark:text-zinc-400">
                    {req.email}
                  </p>
                  <p className="text-xs text-zinc-500 dark:text-zinc-400">
                    {t.requestedAtLabel}: {req.requested_at?.slice(0, 10)}
                  </p>
                </div>
                <select
                  value={requestRole[req.id] ?? "branch_manager"}
                  onChange={(e) =>
                    setRequestRole((prev) => ({
                      ...prev,
                      [req.id]: e.target.value as Role,
                    }))
                  }
                  className="h-9 rounded-md border border-zinc-300 px-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
                >
                  {ROLES.map((r) => (
                    <option key={r} value={r}>
                      {t[ROLE_LABEL_KEY[r]]}
                    </option>
                  ))}
                </select>
                <select
                  value={requestLocation[req.id] ?? ""}
                  onChange={(e) =>
                    setRequestLocation((prev) => ({
                      ...prev,
                      [req.id]: e.target.value,
                    }))
                  }
                  className="h-9 rounded-md border border-zinc-300 px-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
                >
                  <option value="">{t.noneValue}</option>
                  {locations.map((loc) => (
                    <option key={loc.id} value={loc.id}>
                      {locationName(loc)}
                    </option>
                  ))}
                </select>
                <button
                  type="button"
                  onClick={() => handleApprove(req.id)}
                  className="bg-fluffy-orange h-9 rounded-md px-3 text-sm font-medium text-white"
                >
                  {t.approveValue}
                </button>
                <button
                  type="button"
                  onClick={() => handleReject(req.id)}
                  className="h-9 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
                >
                  {t.rejectValue}
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 md:flex-row">
        <div className="flex w-full flex-col gap-2 md:w-64 md:shrink-0">
          <h2 className="text-lg font-semibold">{t.usersListTitle}</h2>
          <ul className="flex flex-col divide-y divide-zinc-100 rounded-md border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {users.map((u) => (
              <li key={u.id}>
                <button
                  type="button"
                  onClick={() => setSelectedId(u.id)}
                  className={`flex w-full flex-col items-start gap-0.5 p-3 text-start text-sm ${
                    selectedId === u.id
                      ? "bg-fluffy-orange/10"
                      : "hover:bg-zinc-50 dark:hover:bg-zinc-900"
                  }`}
                >
                  <span className="font-medium">{u.full_name}</span>
                  <span className="text-xs text-zinc-500 dark:text-zinc-400">
                    {u.email || "—"}
                  </span>
                  <span className="flex items-center gap-1.5 text-xs text-zinc-500 dark:text-zinc-400">
                    {t[ROLE_LABEL_KEY[u.role]]}
                    {!u.active && <Pill tone="red">{t.inactiveLabel}</Pill>}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </div>

        <div className="flex-1">
          {!selectedUser ? (
            <p className="p-6 text-center text-sm text-zinc-500 dark:text-zinc-400">
              {t.selectUserPrompt}
            </p>
          ) : (
            <div className="flex flex-col gap-6">
              <div className="flex flex-col gap-3 rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
                <h2 className="text-lg font-semibold">{t.userInfoTitle}</h2>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <p className="text-sm">
                    <span className="text-zinc-500 dark:text-zinc-400">
                      {t.email}:{" "}
                    </span>
                    {selectedUser.email || "—"}
                  </p>
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={selectedUser.active}
                      onChange={(e) =>
                        updateSelectedUser({ active: e.target.checked })
                      }
                      className="h-5 w-5 rounded border-zinc-300 dark:border-zinc-700"
                    />
                    {t.activeLabel}
                  </label>
                  <label className="flex flex-col gap-1 text-sm">
                    {t.assignRoleLabel}
                    <select
                      value={selectedUser.role}
                      onChange={(e) =>
                        updateSelectedUser({
                          role: e.target.value as Role,
                        })
                      }
                      className="h-9 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
                    >
                      {ROLES.map((r) => (
                        <option key={r} value={r}>
                          {t[ROLE_LABEL_KEY[r]]}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="flex flex-col gap-1 text-sm">
                    {t.primaryBranchLabel}
                    <select
                      value={selectedUser.location_id ?? ""}
                      onChange={(e) =>
                        updateSelectedUser({
                          location_id: e.target.value || null,
                        })
                      }
                      className="h-9 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
                    >
                      <option value="">{t.noneValue}</option>
                      {locations.map((loc) => (
                        <option key={loc.id} value={loc.id}>
                          {locationName(loc)}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>
              </div>

              <div className="flex flex-col gap-2 rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
                <h2 className="text-lg font-semibold">
                  {t.branchesLinkedTitle}
                </h2>
                {selectedUser.role !== "branch_manager" ? (
                  <p className="text-sm text-zinc-500 dark:text-zinc-400">
                    {t.noneValue}
                  </p>
                ) : (
                  <>
                    <p className="text-sm text-zinc-500 dark:text-zinc-400">
                      {t.additionalBranchesLabel}
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {locations.map((loc) => {
                        const isOwn = selectedUser.location_id === loc.id;
                        const granted =
                          isOwn ||
                          grantedLocations.some((g) => g.id === loc.id);
                        return (
                          <button
                            key={loc.id}
                            type="button"
                            disabled={isOwn}
                            onClick={() => toggleGrant(loc.id, granted)}
                            className={`h-8 rounded-full border px-3 text-xs font-medium ${
                              granted
                                ? "border-fluffy-orange bg-fluffy-orange text-white"
                                : "border-zinc-300 dark:border-zinc-700"
                            } ${isOwn ? "opacity-70" : ""}`}
                          >
                            {locationName(loc)}
                            {isOwn ? ` (${t.ownBranchLabel})` : ""}
                          </button>
                        );
                      })}
                    </div>
                  </>
                )}
              </div>

              <div className="flex flex-col gap-2 rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
                <h2 className="text-lg font-semibold">
                  {t.modulesVisibleTitle}
                </h2>
                <div className="flex flex-wrap gap-2">
                  {visibleModules.map((label) => (
                    <Pill key={label} tone="zinc">
                      {label}
                    </Pill>
                  ))}
                </div>
              </div>

              <div className="flex flex-col gap-2 rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
                <h2 className="text-lg font-semibold">{t.activityLogTitle}</h2>
                {activity.length === 0 ? (
                  <p className="text-sm text-zinc-500 dark:text-zinc-400">
                    {t.noActivityYet}
                  </p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-max text-sm">
                      <thead className="bg-zinc-50 dark:bg-zinc-900">
                        <tr>
                          <th className="p-2 text-start">{t.dateLabel}</th>
                          <th className="p-2 text-start">{t.moduleLabel}</th>
                          <th className="p-2 text-start">{t.actionLabel}</th>
                          <th className="p-2 text-start">
                            {t.descriptionLabel}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {activity.map((row, i) => (
                          <tr
                            key={`${row.source_table}-${row.record_id}-${i}`}
                            className="border-t border-zinc-100 dark:border-zinc-800"
                          >
                            <td className="p-2">
                              {row.created_at?.slice(0, 16).replace("T", " ")}
                            </td>
                            <td className="p-2">{row.source_table}</td>
                            <td className="p-2">{row.action}</td>
                            <td className="max-w-xs truncate p-2">
                              {row.detail || "—"}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}

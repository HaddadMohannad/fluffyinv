import { useEffect, useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

// Locations a profile can audit: admins see every branch (matching how
// admin location access works everywhere else in the app); a branch
// manager or inspector sees their own location (if any) plus anything
// granted to them in audit_location_grants (FLU-48); everyone else sees
// none, since only admin/branch_manager/inspector can write audits.
export function useAuditLocations() {
  const { profile } = useAuth();
  const [locations, setLocations] = useState<Tables<"locations">[]>([]);

  useEffect(() => {
    if (!profile) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when the profile isn't loaded yet
      setLocations([]);
      return;
    }

    if (profile.role === "admin") {
      supabase
        .from("locations")
        .select("*")
        .order("name_en")
        .then(({ data }) => setLocations(data ?? []));
      return;
    }

    if (profile.role !== "branch_manager" && profile.role !== "inspector") {
      setLocations([]);
      return;
    }

    supabase
      .from("audit_location_grants")
      .select("location_id")
      .eq("profile_id", profile.id)
      .then(({ data }) => {
        const ids = new Set((data ?? []).map((g) => g.location_id));
        if (profile.location_id) ids.add(profile.location_id);
        if (ids.size === 0) {
          setLocations([]);
          return;
        }
        supabase
          .from("locations")
          .select("*")
          .in("id", Array.from(ids))
          .order("name_en")
          .then(({ data: locs }) => setLocations(locs ?? []));
      });
  }, [profile]);

  return locations;
}

import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const STORAGE_KEY = "fluffy_selected_location_id";

type LocationState = {
  locations: Tables<"locations">[];
  locationId: string;
  isLocationLocked: boolean;
  setSelectedLocationId: (id: string) => void;
};

const LocationContext = createContext<LocationState | null>(null);

export function LocationProvider({ children }: { children: ReactNode }) {
  const { profile } = useAuth();
  const isLocationLocked = profile?.role !== "admin";

  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [selectedLocationId, setSelectedLocationId] = useState(
    () => localStorage.getItem(STORAGE_KEY) ?? ""
  );

  useEffect(() => {
    if (!profile) return;
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
  }, [profile]);

  // Default (or recover from a stale/deleted id) to the first location once
  // the list loads, for admins only -- branch_manager/warehouse_staff are
  // locked to profile.location_id and never use this state.
  useEffect(() => {
    if (isLocationLocked || locations.length === 0) return;
    if (!locations.some((l) => l.id === selectedLocationId)) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- recovering a stale/missing selection once the location list loads
      setSelectedLocationId(locations[0].id);
    }
  }, [isLocationLocked, locations, selectedLocationId]);

  useEffect(() => {
    if (isLocationLocked || !selectedLocationId) return;
    localStorage.setItem(STORAGE_KEY, selectedLocationId);
  }, [isLocationLocked, selectedLocationId]);

  const locationId = isLocationLocked
    ? (profile?.location_id ?? "")
    : selectedLocationId;

  return (
    <LocationContext.Provider
      value={{ locations, locationId, isLocationLocked, setSelectedLocationId }}
    >
      {children}
    </LocationContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useActiveLocation() {
  const ctx = useContext(LocationContext);
  if (!ctx)
    throw new Error("useActiveLocation must be used within LocationProvider");
  return ctx;
}

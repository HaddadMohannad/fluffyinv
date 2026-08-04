import { useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { BranchSelectionPage } from "@/pages/BranchSelectionPage";
import { DashboardPage } from "@/pages/DashboardPage";

export function HomePage() {
  const { session, profile } = useAuth();
  const { t } = useLocale();
  const { isLocationLocked, setSelectedLocationId } = useActiveLocation();
  const [branchPicked, setBranchPicked] = useState(isLocationLocked);

  if (!profile) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {session?.user.email}: {t.noProfile}
      </div>
    );
  }

  if (!branchPicked) {
    return (
      <BranchSelectionPage
        onSelect={(id) => {
          setSelectedLocationId(id);
          setBranchPicked(true);
        }}
      />
    );
  }

  return <DashboardPage />;
}

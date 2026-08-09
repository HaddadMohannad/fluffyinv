import { useEffect, useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { BranchSelectionPage } from "@/pages/BranchSelectionPage";
import { DashboardPage } from "@/pages/DashboardPage";

function PendingApprovalNotice() {
  const { session, signOut } = useAuth();
  const { t } = useLocale();
  const [request, setRequest] = useState<Tables<"signup_requests"> | null>(
    null
  );
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!session?.user.id) return;
    supabase
      .from("signup_requests")
      .select("*")
      .eq("id", session.user.id)
      .maybeSingle()
      .then(({ data }) => {
        setRequest(data);
        setLoading(false);
      });
  }, [session?.user.id]);

  const message = loading
    ? t.noProfile
    : request?.status === "rejected"
      ? t.signupRejected
      : t.signupPending;

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
      <p>
        {session?.user.email}: {message}
      </p>
      <button
        type="button"
        onClick={() => signOut()}
        className="text-fluffy-orange text-sm font-medium"
      >
        {t.signOut}
      </button>
    </div>
  );
}

export function HomePage() {
  const { profile } = useAuth();
  const { isLocationLocked, setSelectedLocationId } = useActiveLocation();
  const [branchPicked, setBranchPicked] = useState(isLocationLocked);

  if (!profile) {
    return <PendingApprovalNotice />;
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

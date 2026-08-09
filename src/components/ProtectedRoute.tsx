import { Navigate, Outlet, useLocation } from "react-router";
import { useAuth } from "@/lib/auth/AuthContext";

export function ProtectedRoute() {
  const { session, profile, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return (
      <div className="flex flex-1 items-center justify-center">
        <p className="text-sm text-zinc-500">Loading…</p>
      </div>
    );
  }

  if (!session) {
    return <Navigate to="/login" replace />;
  }

  // A session with no profile yet (pending/rejected signup) can only ever
  // see "/", which renders the pending-approval message — every other
  // route is off-limits until an admin approves the account.
  if (!profile && location.pathname !== "/") {
    return <Navigate to="/" replace />;
  }

  return <Outlet />;
}

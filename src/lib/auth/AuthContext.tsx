import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type AuthState = {
  session: Session | null;
  profile: Tables<"profiles"> | null;
  location: Tables<"locations"> | null;
  loading: boolean;
  signIn: (
    email: string,
    password: string
  ) => Promise<{ error: string | null }>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Tables<"profiles"> | null>(null);
  const [location, setLocation] = useState<Tables<"locations"> | null>(null);
  const [sessionLoading, setSessionLoading] = useState(true);
  const [profileLoading, setProfileLoading] = useState(true);

  useEffect(() => {
    let active = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      setSession(data.session);
      setSessionLoading(false);
    });

    const { data: subscription } = supabase.auth.onAuthStateChange(
      (_event, newSession) => {
        setSession(newSession);
        setSessionLoading(false);
      }
    );

    return () => {
      active = false;
      subscription.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (sessionLoading) return;

    let active = true;

    async function loadProfile() {
      if (!session?.user) {
        setProfile(null);
        setLocation(null);
        setProfileLoading(false);
        return;
      }

      setProfileLoading(true);

      const { data: profileData } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", session.user.id)
        .single();

      if (!active) return;
      setProfile(profileData ?? null);

      if (profileData?.location_id) {
        const { data: locationData } = await supabase
          .from("locations")
          .select("*")
          .eq("id", profileData.location_id)
          .single();
        if (active) setLocation(locationData ?? null);
      } else {
        setLocation(null);
      }

      if (active) setProfileLoading(false);
    }

    loadProfile();

    return () => {
      active = false;
    };
  }, [session?.user, sessionLoading]);

  async function signIn(email: string, password: string) {
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (!error) return { error: null };

      console.error("signIn error:", {
        name: error.name,
        status: error.status,
        code: error.code,
        message: error.message,
      });

      const message =
        typeof error.message === "string" && error.message.trim().length > 0
          ? error.message
          : `Sign-in failed (${error.name ?? "unknown"}${error.status ? `, HTTP ${error.status}` : ""}). Check the browser console for details.`;

      return { error: message };
    } catch (err) {
      console.error("signIn threw:", err);
      return {
        error:
          "Could not reach the sign-in service. Check your connection and try again.",
      };
    }
  }

  async function signOut() {
    await supabase.auth.signOut();
  }

  return (
    <AuthContext.Provider
      value={{
        session,
        profile,
        location,
        loading: sessionLoading || profileLoading,
        signIn,
        signOut,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

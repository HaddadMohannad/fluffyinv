import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

export type CurrentUser = {
  id: string;
  email: string | undefined;
  profile: Tables<"profiles"> | null;
  location: Tables<"locations"> | null;
};

export async function getCurrentUser(): Promise<CurrentUser | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single();

  let location: Tables<"locations"> | null = null;
  if (profile?.location_id) {
    const { data } = await supabase
      .from("locations")
      .select("*")
      .eq("id", profile.location_id)
      .single();
    location = data ?? null;
  }

  return { id: user.id, email: user.email, profile: profile ?? null, location };
}

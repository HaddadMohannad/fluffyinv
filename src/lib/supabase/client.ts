import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    "Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY environment variables."
  );
}

/**
 * Browser-only client using the public anon key. This app is a static
 * site with no server component — never use the service-role key here,
 * it would be bundled and exposed to every visitor. RLS policies are the
 * real access-control boundary.
 */
export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey);

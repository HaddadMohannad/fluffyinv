const REMEMBER_KEY = "fluffy_remember_me";

/**
 * Must be called before signing in so the session that gets written during
 * signInWithPassword lands in the right storage.
 */
export function setRememberMe(remember: boolean) {
  localStorage.setItem(REMEMBER_KEY, remember ? "true" : "false");
}

function getRememberMe(): boolean {
  // Default true so sessions created before this feature shipped keep working.
  return localStorage.getItem(REMEMBER_KEY) !== "false";
}

/**
 * Storage adapter for the Supabase client: writes the session to
 * localStorage (persists across browser restarts) when "remember me" is on,
 * or sessionStorage (cleared when the tab/browser closes) when it's off.
 * Reads check both, since an existing session may have been written before
 * the user's current remember-me preference was set.
 */
export const rememberableStorage = {
  getItem(key: string) {
    return sessionStorage.getItem(key) ?? localStorage.getItem(key);
  },
  setItem(key: string, value: string) {
    if (getRememberMe()) {
      localStorage.setItem(key, value);
      sessionStorage.removeItem(key);
    } else {
      sessionStorage.setItem(key, value);
      localStorage.removeItem(key);
    }
  },
  removeItem(key: string) {
    localStorage.removeItem(key);
    sessionStorage.removeItem(key);
  },
};

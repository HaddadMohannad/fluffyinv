import { useEffect, useState } from "react";

// The app has no manual theme toggle — dark mode follows the OS/browser
// preference everywhere (Tailwind's dark: variant already keys off this),
// so chart chrome colors (which recharts takes as literal props, not CSS
// classes) need the same signal.
export function useIsDarkMode() {
  const [isDark, setIsDark] = useState(
    () => window.matchMedia("(prefers-color-scheme: dark)").matches
  );

  useEffect(() => {
    const mql = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = (e: MediaQueryListEvent) => setIsDark(e.matches);
    mql.addEventListener("change", handler);
    return () => mql.removeEventListener("change", handler);
  }, []);

  return isDark;
}

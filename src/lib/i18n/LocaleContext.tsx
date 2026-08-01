import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import {
  dictionary,
  dir,
  locales,
  type Locale,
  type Strings,
} from "./dictionary";

const STORAGE_KEY = "fluffy_locale";

function readStoredLocale(): Locale {
  const stored = localStorage.getItem(STORAGE_KEY);
  return (locales as readonly string[]).includes(stored ?? "")
    ? (stored as Locale)
    : "en";
}

type LocaleState = {
  locale: Locale;
  t: Strings;
  setLocale: (locale: Locale) => void;
};

const LocaleContext = createContext<LocaleState | null>(null);

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(readStoredLocale);

  useEffect(() => {
    document.documentElement.lang = locale;
    document.documentElement.dir = dir(locale);
    localStorage.setItem(STORAGE_KEY, locale);
  }, [locale]);

  return (
    <LocaleContext.Provider
      value={{ locale, t: dictionary[locale], setLocale: setLocaleState }}
    >
      {children}
    </LocaleContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useLocale() {
  const ctx = useContext(LocaleContext);
  if (!ctx) throw new Error("useLocale must be used within LocaleProvider");
  return ctx;
}

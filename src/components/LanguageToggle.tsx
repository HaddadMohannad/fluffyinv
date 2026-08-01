import { useLocale } from "@/lib/i18n/LocaleContext";

export function LanguageToggle() {
  const { locale, t, setLocale } = useLocale();
  const nextLocale = locale === "en" ? "ar" : "en";

  return (
    <button
      type="button"
      onClick={() => setLocale(nextLocale)}
      className="h-11 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
    >
      {t.switchToLabel}
    </button>
  );
}

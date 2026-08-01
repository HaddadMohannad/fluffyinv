"use client";

import { useTransition } from "react";
import { setLocale } from "@/app/actions/locale";
import type { Locale } from "@/lib/i18n/dictionary";

export function LanguageToggle({
  locale,
  label,
}: {
  locale: Locale;
  label: string;
}) {
  const [pending, startTransition] = useTransition();
  const nextLocale: Locale = locale === "en" ? "ar" : "en";

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => startTransition(() => setLocale(nextLocale))}
      className="h-11 rounded-md border border-zinc-300 px-3 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
    >
      {label}
    </button>
  );
}

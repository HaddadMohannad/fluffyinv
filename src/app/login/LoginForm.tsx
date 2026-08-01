"use client";

import { useActionState } from "react";
import { signIn, type SignInState } from "@/app/actions/auth";
import { LanguageToggle } from "@/components/LanguageToggle";
import type { Locale } from "@/lib/i18n/dictionary";
import { dictionary } from "@/lib/i18n/dictionary";

const initialState: SignInState = { error: null };

export function LoginForm({ locale }: { locale: Locale }) {
  const [state, formAction, pending] = useActionState(signIn, initialState);
  const t = dictionary[locale];

  return (
    <div className="flex flex-1 flex-col">
      <div className="flex justify-end p-4">
        <LanguageToggle locale={locale} label={t.switchToLabel} />
      </div>
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <form action={formAction} className="w-full max-w-sm space-y-4">
          <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
            {t.signIn}
          </h1>
          <div className="space-y-1">
            <label htmlFor="email" className="text-sm font-medium">
              {t.email}
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              autoComplete="email"
              className="h-11 w-full rounded-md border border-zinc-300 px-3 text-base dark:border-zinc-700 dark:bg-zinc-900"
            />
          </div>
          <div className="space-y-1">
            <label htmlFor="password" className="text-sm font-medium">
              {t.password}
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="current-password"
              className="h-11 w-full rounded-md border border-zinc-300 px-3 text-base dark:border-zinc-700 dark:bg-zinc-900"
            />
          </div>
          {state.error && <p className="text-sm text-red-600">{state.error}</p>}
          <button
            type="submit"
            disabled={pending}
            className="bg-fluffy-orange h-11 w-full rounded-md text-base font-medium text-white disabled:opacity-60"
          >
            {pending ? t.signingIn : t.signIn}
          </button>
        </form>
      </div>
    </div>
  );
}

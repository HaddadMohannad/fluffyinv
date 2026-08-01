import { useState, type FormEvent } from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { LanguageToggle } from "@/components/LanguageToggle";

export function LoginPage() {
  const { session, loading, signIn } = useAuth();
  const { t } = useLocale();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  if (!loading && session) {
    return <Navigate to="/" replace />;
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const formData = new FormData(e.currentTarget);
    const email = formData.get("email") as string;
    const password = formData.get("password") as string;

    const { error: signInError } = await signIn(email, password);
    setPending(false);
    if (signInError) setError(signInError);
  }

  return (
    <div className="flex flex-1 flex-col">
      <div className="flex justify-end p-4">
        <LanguageToggle />
      </div>
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <form onSubmit={handleSubmit} className="w-full max-w-sm space-y-4">
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
          {error && <p className="text-sm text-red-600">{error}</p>}
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

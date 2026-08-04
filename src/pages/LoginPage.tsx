import { useState, type FormEvent } from "react";
import { Navigate } from "react-router";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { LanguageToggle } from "@/components/LanguageToggle";

type Mode = "signin" | "forgot";

export function LoginPage() {
  const { session, loading } = useAuth();
  const [mode, setMode] = useState<Mode>("signin");

  if (!loading && session) {
    return <Navigate to="/" replace />;
  }

  return (
    <div className="flex flex-1 flex-col">
      <div className="flex justify-end p-4">
        <LanguageToggle />
      </div>
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        {mode === "signin" ? (
          <SignInForm onForgotPassword={() => setMode("forgot")} />
        ) : (
          <ForgotPasswordForm onBack={() => setMode("signin")} />
        )}
      </div>
    </div>
  );
}

function SignInForm({ onForgotPassword }: { onForgotPassword: () => void }) {
  const { signIn } = useAuth();
  const { t } = useLocale();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [remember, setRemember] = useState(true);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const formData = new FormData(e.currentTarget);
    const email = formData.get("email") as string;
    const password = formData.get("password") as string;

    const { error: signInError } = await signIn(email, password, remember);
    setPending(false);
    if (signInError) setError(signInError);
  }

  return (
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
      <div className="flex items-center justify-between">
        <label className="flex h-11 items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={remember}
            onChange={(e) => setRemember(e.target.checked)}
            className="h-5 w-5 rounded border-zinc-300 dark:border-zinc-700"
          />
          {t.rememberMe}
        </label>
        <button
          type="button"
          onClick={onForgotPassword}
          className="text-fluffy-orange h-11 text-sm font-medium"
        >
          {t.forgotPassword}
        </button>
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
  );
}

function ForgotPasswordForm({ onBack }: { onBack: () => void }) {
  const { requestPasswordReset } = useAuth();
  const { t } = useLocale();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [sent, setSent] = useState(false);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const formData = new FormData(e.currentTarget);
    const email = formData.get("email") as string;

    const { error: resetError } = await requestPasswordReset(email);
    setPending(false);
    if (resetError) {
      setError(resetError);
    } else {
      setSent(true);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="w-full max-w-sm space-y-4">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.resetPasswordTitle}
      </h1>
      {sent ? (
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          {t.resetLinkSent}
        </p>
      ) : (
        <>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.resetPasswordInstructions}
          </p>
          <div className="space-y-1">
            <label htmlFor="reset-email" className="text-sm font-medium">
              {t.email}
            </label>
            <input
              id="reset-email"
              name="email"
              type="email"
              required
              autoComplete="email"
              className="h-11 w-full rounded-md border border-zinc-300 px-3 text-base dark:border-zinc-700 dark:bg-zinc-900"
            />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <button
            type="submit"
            disabled={pending}
            className="bg-fluffy-orange h-11 w-full rounded-md text-base font-medium text-white disabled:opacity-60"
          >
            {pending ? t.sendingResetLink : t.sendResetLink}
          </button>
        </>
      )}
      <button
        type="button"
        onClick={onBack}
        className="h-11 w-full text-sm font-medium text-zinc-600 dark:text-zinc-400"
      >
        {t.backToSignIn}
      </button>
    </form>
  );
}

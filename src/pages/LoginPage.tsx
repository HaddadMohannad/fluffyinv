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
  const { signIn, signInWithGoogle } = useAuth();
  const { t } = useLocale();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [googlePending, setGooglePending] = useState(false);
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

  async function handleGoogleClick() {
    setGooglePending(true);
    setError(null);
    const { error: googleError } = await signInWithGoogle();
    if (googleError) {
      setGooglePending(false);
      setError(googleError);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="w-full max-w-sm space-y-4">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.signIn}
      </h1>
      <button
        type="button"
        onClick={handleGoogleClick}
        disabled={googlePending}
        className="flex h-11 w-full items-center justify-center gap-2 rounded-md border border-zinc-300 text-sm font-medium disabled:opacity-60 dark:border-zinc-700"
      >
        <svg viewBox="0 0 24 24" className="h-4 w-4" aria-hidden="true">
          <path
            fill="#4285F4"
            d="M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.47a5.53 5.53 0 0 1-2.4 3.63v3h3.87c2.27-2.09 3.58-5.17 3.58-8.82Z"
          />
          <path
            fill="#34A853"
            d="M12 24c3.24 0 5.96-1.07 7.94-2.91l-3.87-3c-1.08.72-2.45 1.15-4.07 1.15-3.13 0-5.78-2.11-6.73-4.96H1.28v3.11A12 12 0 0 0 12 24Z"
          />
          <path
            fill="#FBBC05"
            d="M5.27 14.28A7.2 7.2 0 0 1 4.89 12c0-.79.14-1.56.38-2.28V6.61H1.28A12 12 0 0 0 0 12c0 1.94.46 3.77 1.28 5.39l3.99-3.11Z"
          />
          <path
            fill="#EA4335"
            d="M12 4.77c1.77 0 3.35.61 4.6 1.8l3.44-3.44C17.95 1.19 15.24 0 12 0A12 12 0 0 0 1.28 6.61l3.99 3.11C6.22 6.88 8.87 4.77 12 4.77Z"
          />
        </svg>
        {googlePending ? t.signingIn : t.signInWithGoogle}
      </button>
      <div className="flex items-center gap-3 text-xs text-zinc-500 dark:text-zinc-400">
        <span className="h-px flex-1 bg-zinc-200 dark:bg-zinc-800" />
        {t.orDivider}
        <span className="h-px flex-1 bg-zinc-200 dark:bg-zinc-800" />
      </div>
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

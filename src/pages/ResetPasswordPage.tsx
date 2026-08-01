import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { LanguageToggle } from "@/components/LanguageToggle";

export function ResetPasswordPage() {
  const { updatePassword } = useAuth();
  const { t } = useLocale();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [done, setDone] = useState(false);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    const formData = new FormData(e.currentTarget);
    const password = formData.get("password") as string;
    const confirmPassword = formData.get("confirmPassword") as string;

    if (password !== confirmPassword) {
      setError(t.passwordMismatch);
      return;
    }

    setPending(true);
    const { error: updateError } = await updatePassword(password);
    setPending(false);

    if (updateError) {
      setError(updateError);
    } else {
      setDone(true);
    }
  }

  return (
    <div className="flex flex-1 flex-col">
      <div className="flex justify-end p-4">
        <LanguageToggle />
      </div>
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <div className="w-full max-w-sm space-y-4">
          <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
            {t.newPasswordTitle}
          </h1>
          {done ? (
            <>
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                {t.passwordUpdated}
              </p>
              <Link
                to="/login"
                className="bg-fluffy-orange flex h-11 w-full items-center justify-center rounded-md text-base font-medium text-white"
              >
                {t.backToSignIn}
              </Link>
            </>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-1">
                <label htmlFor="password" className="text-sm font-medium">
                  {t.newPassword}
                </label>
                <input
                  id="password"
                  name="password"
                  type="password"
                  required
                  autoComplete="new-password"
                  className="h-11 w-full rounded-md border border-zinc-300 px-3 text-base dark:border-zinc-700 dark:bg-zinc-900"
                />
              </div>
              <div className="space-y-1">
                <label
                  htmlFor="confirmPassword"
                  className="text-sm font-medium"
                >
                  {t.confirmPassword}
                </label>
                <input
                  id="confirmPassword"
                  name="confirmPassword"
                  type="password"
                  required
                  autoComplete="new-password"
                  className="h-11 w-full rounded-md border border-zinc-300 px-3 text-base dark:border-zinc-700 dark:bg-zinc-900"
                />
              </div>
              {error && <p className="text-sm text-red-600">{error}</p>}
              <button
                type="submit"
                disabled={pending}
                className="bg-fluffy-orange h-11 w-full rounded-md text-base font-medium text-white disabled:opacity-60"
              >
                {pending ? t.updatingPassword : t.updatePassword}
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}

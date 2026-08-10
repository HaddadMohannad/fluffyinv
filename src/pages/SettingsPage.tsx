import { useState } from "react";
import { AlertTriangle } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";

const CONFIRM_PHRASE = "DELETE ALL DATA";

export function SettingsPage() {
  const { profile } = useAuth();
  const { t } = useLocale();

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  if (profile?.role !== "admin") {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function closeConfirm() {
    setConfirmOpen(false);
    setConfirmText("");
    setError(null);
  }

  async function handleDeleteAll() {
    setDeleting(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc("delete_all_business_data");
    setDeleting(false);

    if (rpcError) {
      console.error("Delete all business data failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    closeConfirm();
    setMessage(t.deleteAllDataSuccess);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.settingsTitle}
      </h1>

      {message && <p className="text-sm text-green-600">{message}</p>}

      <section className="max-w-xl rounded-xl border border-red-300 bg-red-50 p-4 dark:border-red-900 dark:bg-red-950/40">
        <h2 className="mb-1 flex items-center gap-2 text-lg font-semibold text-red-700 dark:text-red-400">
          <AlertTriangle className="h-5 w-5" />
          {t.dangerZoneTitle}
        </h2>
        <p className="mb-4 text-sm text-red-800 dark:text-red-300">
          {t.dangerZoneDescription}
        </p>
        <button
          type="button"
          onClick={() => setConfirmOpen(true)}
          className="h-11 rounded-md bg-red-600 px-4 text-sm font-medium text-white hover:bg-red-700"
        >
          {t.deleteAllDataButton}
        </button>
      </section>

      {confirmOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={closeConfirm}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-md rounded-xl bg-white p-6 dark:bg-zinc-900"
          >
            <h3 className="mb-2 text-lg font-semibold text-red-700 dark:text-red-400">
              {t.deleteAllDataConfirmTitle}
            </h3>
            <p className="mb-4 text-sm text-zinc-700 dark:text-zinc-300">
              {t.deleteAllDataConfirmBody}
            </p>
            <p className="mb-3 rounded-md bg-zinc-100 px-3 py-2 text-center font-mono text-sm font-semibold tracking-wide dark:bg-zinc-800">
              {CONFIRM_PHRASE}
            </p>
            <label className="mb-1 flex flex-col gap-1 text-sm">
              {t.confirmPhraseLabel}
              <input
                type="text"
                value={confirmText}
                onChange={(e) => setConfirmText(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 font-mono dark:border-zinc-700 dark:bg-zinc-900"
                autoFocus
              />
            </label>
            {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={closeConfirm}
                className="h-11 rounded-md border border-zinc-300 px-4 text-sm font-medium dark:border-zinc-700"
              >
                {t.cancelButton}
              </button>
              <button
                type="button"
                disabled={confirmText !== CONFIRM_PHRASE || deleting}
                onClick={handleDeleteAll}
                className="h-11 rounded-md bg-red-600 px-4 text-sm font-medium text-white disabled:opacity-40"
              >
                {deleting ? t.deletingAllData : t.deleteAllDataButton}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

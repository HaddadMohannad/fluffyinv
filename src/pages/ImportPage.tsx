import { useRef, useState, type DragEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import { fileToRows } from "@/lib/imports/parse";
import { detectAdapter } from "@/lib/imports/adapters";
import { importOrders, type ImportRunResult } from "@/lib/imports/importer";
import type { NormalizeResult, SourceAdapter } from "@/lib/imports/types";

type FoodicsSyncResult = {
  windowFrom: string;
  totalFetched: number;
  resolvedCount: number;
  unresolvedCount: number;
  invalidCount: number;
  insertedCount: number;
  lineMatchedCount: number;
  lineUnmatchedCount: number;
};

type FoodicsSyncState =
  | { step: "idle" }
  | { step: "syncing" }
  | { step: "done"; result: FoodicsSyncResult }
  | { step: "error"; message: string };

type Preview = {
  adapter: SourceAdapter;
  filename: string;
  result: NormalizeResult;
};

type Stage =
  | { step: "idle" }
  | { step: "unrecognized" }
  | { step: "preview"; preview: Preview }
  | { step: "importing"; preview: Preview }
  | { step: "done"; summary: ImportRunResult };

export function ImportPage() {
  const { session, profile } = useAuth();
  const { t } = useLocale();
  const [stage, setStage] = useState<Stage>({ step: "idle" });
  const [error, setError] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [foodicsSync, setFoodicsSync] = useState<FoodicsSyncState>({
    step: "idle",
  });

  const canImport = profile?.role === "admin" || profile?.role === "accountant";

  if (!canImport) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        Only admin and accountant accounts can import sales data.
      </div>
    );
  }

  async function handleFile(file: File) {
    setError(null);
    try {
      const { headers, rows } = await fileToRows(file);
      const adapter = detectAdapter(headers);
      if (!adapter) {
        setStage({ step: "unrecognized" });
        return;
      }
      const result = adapter.normalize(rows);
      setStage({
        step: "preview",
        preview: { adapter, filename: file.name, result },
      });
    } catch (err) {
      console.error("Failed to parse file:", err);
      setError(t.cantReadFile);
    }
  }

  async function handleImport() {
    if (stage.step !== "preview" || !session?.user) return;
    const { preview } = stage;
    setStage({ step: "importing", preview });
    setError(null);

    try {
      const summary = await importOrders({
        source: preview.adapter.source,
        filename: preview.filename,
        orders: preview.result.orders,
        uploadedBy: session.user.id,
      });
      setStage({ step: "done", summary });
    } catch (err) {
      console.error("Import failed:", err);
      setError(err instanceof Error ? err.message : t.importFailed);
      setStage({ step: "preview", preview });
    }
  }

  function handleDrop(e: DragEvent<HTMLDivElement>) {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  }

  async function handleFoodicsSync() {
    setFoodicsSync({ step: "syncing" });
    const { data, error: invokeError } = await supabase.functions.invoke<
      FoodicsSyncResult | { error: string }
    >("foodics-sync");

    if (invokeError || !data || "error" in data) {
      const message =
        (data && "error" in data && data.error) ||
        (invokeError instanceof Error
          ? invokeError.message
          : t.foodicsSyncFailed);
      setFoodicsSync({ step: "error", message });
      return;
    }
    setFoodicsSync({ step: "done", result: data });
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.importTitle}
      </h1>

      <FoodicsSyncPanel
        state={foodicsSync}
        onSync={handleFoodicsSync}
        onReset={() => setFoodicsSync({ step: "idle" })}
      />

      {stage.step === "idle" || stage.step === "unrecognized" ? (
        <div
          onDragOver={(e) => {
            e.preventDefault();
            setDragOver(true);
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={handleDrop}
          onClick={() => fileInputRef.current?.click()}
          className={`flex h-40 cursor-pointer flex-col items-center justify-center rounded-md border-2 border-dashed text-center text-sm ${
            dragOver
              ? "border-fluffy-orange bg-orange-50 dark:bg-orange-950"
              : "border-zinc-300 dark:border-zinc-700"
          }`}
        >
          <p>{t.dropzoneText}</p>
          <input
            ref={fileInputRef}
            type="file"
            accept=".csv"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) handleFile(file);
            }}
          />
        </div>
      ) : null}

      {stage.step === "unrecognized" && (
        <p className="text-sm text-red-600">{t.unrecognizedFormat}</p>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}

      {(stage.step === "preview" || stage.step === "importing") && (
        <PreviewPanel
          preview={stage.preview}
          pending={stage.step === "importing"}
          onImport={handleImport}
        />
      )}

      {stage.step === "done" && (
        <DoneSummary
          summary={stage.summary}
          onReset={() => setStage({ step: "idle" })}
        />
      )}
    </div>
  );
}

function FoodicsSyncPanel({
  state,
  onSync,
  onReset,
}: {
  state: FoodicsSyncState;
  onSync: () => void;
  onReset: () => void;
}) {
  const { t } = useLocale();

  return (
    <div className="space-y-3 rounded-md border border-zinc-200 p-4 dark:border-zinc-800">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="font-medium text-zinc-900 dark:text-zinc-100">
            {t.foodicsSyncTitle}
          </h2>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.foodicsSyncDescription}
          </p>
        </div>
        <button
          type="button"
          disabled={state.step === "syncing"}
          onClick={onSync}
          className="bg-fluffy-orange h-10 shrink-0 rounded-md px-5 text-sm font-medium text-white disabled:opacity-60"
        >
          {state.step === "syncing" ? t.foodicsSyncing : t.foodicsSyncButton}
        </button>
      </div>

      {state.step === "error" && (
        <p className="text-sm text-red-600">
          {t.foodicsSyncFailed}: {state.message}
        </p>
      )}

      {state.step === "done" && (
        <div className="space-y-3">
          <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            <Stat
              label={t.foodicsOrdersFetched}
              value={state.result.totalFetched}
            />
            <Stat label={t.rowsResolved} value={state.result.resolvedCount} />
            <Stat
              label={t.rowsUnresolved}
              value={state.result.unresolvedCount}
            />
            <Stat label="Inserted" value={state.result.insertedCount} />
            <Stat
              label={t.lineItemsMatchedLabel}
              value={state.result.lineMatchedCount}
            />
            <Stat
              label={t.lineItemsUnmatchedLabel}
              value={state.result.lineUnmatchedCount}
            />
          </dl>
          <button
            type="button"
            onClick={onReset}
            className="h-9 rounded-md border border-zinc-300 px-4 text-sm font-medium dark:border-zinc-700"
          >
            {t.importAnother}
          </button>
        </div>
      )}
    </div>
  );
}

function PreviewPanel({
  preview,
  pending,
  onImport,
}: {
  preview: Preview;
  pending: boolean;
  onImport: () => void;
}) {
  const { t } = useLocale();
  const { adapter, filename, result } = preview;

  return (
    <div className="space-y-4">
      <p className="text-sm text-zinc-600 dark:text-zinc-400">
        {filename} — {t.detectedSource}: <strong>{adapter.label}</strong>
      </p>

      <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
        <Stat
          label={t.rowsTotal}
          value={
            result.orders.length +
            result.excludedCount +
            result.invalidRows.length
          }
        />
        <Stat label={t.rowsExcluded} value={result.excludedCount} />
        <Stat label={t.rowsInvalid} value={result.invalidRows.length} />
      </dl>

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="w-full min-w-max text-sm">
          <thead className="bg-zinc-50 text-start dark:bg-zinc-900">
            <tr>
              <th className="p-2 text-start">Ref</th>
              <th className="p-2 text-start">Branch</th>
              <th className="p-2 text-start">Date</th>
              <th className="p-2 text-end">Gross</th>
              <th className="p-2 text-end">Commission</th>
              <th className="p-2 text-end">Net</th>
            </tr>
          </thead>
          <tbody>
            {result.orders.slice(0, 10).map((order) => (
              <tr
                key={order.externalRef}
                className="border-t border-zinc-100 dark:border-zinc-800"
              >
                <td className="p-2">{order.externalRef}</td>
                <td className="p-2">{order.branchName}</td>
                <td className="p-2">
                  {new Date(order.orderDate).toLocaleDateString()}
                </td>
                <td className="p-2 text-end">{order.gross.toFixed(2)}</td>
                <td className="p-2 text-end">{order.commission.toFixed(2)}</td>
                <td className="p-2 text-end">{order.net.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <button
        type="button"
        disabled={pending || result.orders.length === 0}
        onClick={onImport}
        className="bg-fluffy-orange h-11 rounded-md px-6 text-base font-medium text-white disabled:opacity-60"
      >
        {pending ? t.importing : t.importButton}
      </button>
    </div>
  );
}

function DoneSummary({
  summary,
  onReset,
}: {
  summary: ImportRunResult;
  onReset: () => void;
}) {
  const { t } = useLocale();

  return (
    <div className="space-y-4">
      <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <Stat label={t.rowsTotal} value={summary.totalNormalized} />
        <Stat label={t.rowsResolved} value={summary.resolvedCount} />
        <Stat label={t.rowsUnresolved} value={summary.unresolvedCount} />
        <Stat label="Inserted" value={summary.insertedCount} />
        {summary.lineMatchedCount + summary.lineUnmatchedCount > 0 && (
          <>
            <Stat
              label={t.lineItemsMatchedLabel}
              value={summary.lineMatchedCount}
            />
            <Stat
              label={t.lineItemsUnmatchedLabel}
              value={summary.lineUnmatchedCount}
            />
          </>
        )}
      </dl>
      <button
        type="button"
        onClick={onReset}
        className="h-11 rounded-md border border-zinc-300 px-6 text-base font-medium dark:border-zinc-700"
      >
        {t.importAnother}
      </button>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
      <dt className="text-xs text-zinc-500">{label}</dt>
      <dd className="text-lg font-semibold">{value}</dd>
    </div>
  );
}

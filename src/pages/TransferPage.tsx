import { useEffect, useMemo, useState } from "react";
import { ArrowRight } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { NewTransferModal } from "@/components/NewTransferModal";
import { Pill } from "@/components/Pill";
import { statusTone } from "@/lib/pillColors";

type Transfer = Tables<"transfers">;
type TransferLine = Tables<"transfer_lines">;

type RecentTransfer = Transfer & { transfer_lines: TransferLine[] };

export function TransferPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations } = useActiveLocation();

  const canWrite =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "warehouse_staff";

  const myLocationId = profile?.location_id ?? "";
  const isAdmin = profile?.role === "admin";
  const isWarehouseStaff = profile?.role === "warehouse_staff";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [recent, setRecent] = useState<RecentTransfer[]>([]);
  const [busyTransferId, setBusyTransferId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [showNewTransferModal, setShowNewTransferModal] = useState(false);

  useEffect(() => {
    if (!canWrite) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canWrite]);

  useEffect(() => {
    if (!canWrite) return;
    let query = supabase
      .from("transfers")
      .select("*, transfer_lines(*)")
      .order("created_at", { ascending: false })
      .limit(20);
    if (!isAdmin && !isWarehouseStaff) {
      query = query.or(
        `from_location.eq.${myLocationId},to_location.eq.${myLocationId}`
      );
    }
    query.then(({ data }) => setRecent((data as RecentTransfer[]) ?? []));
  }, [canWrite, isAdmin, isWarehouseStaff, myLocationId, refreshKey]);

  const productName = useMemo(() => {
    const map = new Map(
      products.map((p) => [p.id, locale === "ar" ? p.name_ar : p.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [products, locale]);

  const locationName = useMemo(() => {
    const map = new Map(
      locations.map((l) => [l.id, locale === "ar" ? l.name_ar : l.name_en])
    );
    return (id: string) => map.get(id) ?? id;
  }, [locations, locale]);

  const statusLabel = useMemo(() => {
    const labels: Record<Transfer["status"], string> = {
      pending: t.transferStatusPending,
      completed: t.transferStatusCompleted,
      cancelled: t.transferStatusCancelled,
    };
    return (status: Transfer["status"]) => labels[status];
  }, [t]);

  if (!canWrite) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function canConfirm(transfer: Transfer) {
    return isAdmin || isWarehouseStaff || transfer.to_location === myLocationId;
  }

  function canCancel(transfer: Transfer) {
    return (
      isAdmin ||
      isWarehouseStaff ||
      transfer.from_location === myLocationId ||
      transfer.to_location === myLocationId
    );
  }

  function handleSaved() {
    setRefreshKey((k) => k + 1);
  }

  async function handleConfirm(transferId: string) {
    setBusyTransferId(transferId);
    setError(null);
    const { error: rpcError } = await supabase.rpc("complete_transfer", {
      p_transfer_id: transferId,
    });
    setBusyTransferId(null);
    if (rpcError) {
      console.error("Confirm receipt failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  async function handleCancel(transferId: string) {
    setBusyTransferId(transferId);
    setError(null);
    const { error: rpcError } = await supabase.rpc("cancel_transfer", {
      p_transfer_id: transferId,
    });
    setBusyTransferId(null);
    if (rpcError) {
      console.error("Cancel transfer failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.transferTitle}
        </h1>
        <button
          type="button"
          onClick={() => setShowNewTransferModal(true)}
          className="bg-fluffy-orange h-9 rounded-md px-4 text-sm font-medium text-white"
        >
          {t.createTransfer}
        </button>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <section>
        <h2 className="mb-2 text-lg font-semibold">{t.recentTransfersTitle}</h2>
        {recent.length === 0 ? (
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.noRecentTransfers}
          </p>
        ) : (
          <div className="flex flex-col gap-3">
            {recent.map((transfer) => (
              <div
                key={transfer.id}
                className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800"
              >
                <div className="mb-2 flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2 text-sm font-medium">
                    <span>{locationName(transfer.from_location)}</span>
                    <ArrowRight className="h-4 w-4 text-zinc-400 rtl:rotate-180" />
                    <span>{locationName(transfer.to_location)}</span>
                  </div>
                  <Pill tone={statusTone(transfer.status)}>
                    {statusLabel(transfer.status)}
                  </Pill>
                </div>
                <ul className="mb-2 flex flex-col gap-1 text-sm text-zinc-600 dark:text-zinc-400">
                  {transfer.transfer_lines.map((line) => (
                    <li key={line.id}>
                      {productName(line.product_id)} — {line.qty}
                    </li>
                  ))}
                </ul>
                {transfer.status === "pending" && (
                  <div className="flex gap-2">
                    {canConfirm(transfer) && (
                      <button
                        type="button"
                        disabled={busyTransferId === transfer.id}
                        onClick={() => handleConfirm(transfer.id)}
                        className="bg-fluffy-orange h-9 rounded-md px-3 text-xs font-medium text-white disabled:opacity-60"
                      >
                        {busyTransferId === transfer.id
                          ? t.confirmingReceipt
                          : t.confirmReceipt}
                      </button>
                    )}
                    {canCancel(transfer) && (
                      <button
                        type="button"
                        disabled={busyTransferId === transfer.id}
                        onClick={() => handleCancel(transfer.id)}
                        className="h-9 rounded-md border border-zinc-300 px-3 text-xs font-medium disabled:opacity-60 dark:border-zinc-700"
                      >
                        {busyTransferId === transfer.id
                          ? t.cancellingTransfer
                          : t.cancelTransfer}
                      </button>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </section>

      {showNewTransferModal && (
        <NewTransferModal
          onClose={() => setShowNewTransferModal(false)}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}

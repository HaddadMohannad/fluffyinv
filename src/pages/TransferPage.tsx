import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type Transfer = Tables<"transfers">;
type TransferLine = Tables<"transfer_lines">;

type PendingTransfer = Transfer & { transfer_lines: TransferLine[] };

type DraftLine = { product_id: string; name: string; qty: string };

export function TransferPage() {
  const { profile } = useAuth();
  const { t } = useLocale();

  const canWrite =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "warehouse_staff";

  const myLocationId = profile?.location_id ?? "";
  const isAdmin = profile?.role === "admin";
  const isWarehouseStaff = profile?.role === "warehouse_staff";

  const [locations, setLocations] = useState<Tables<"locations">[]>([]);
  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [fromLocationId, setFromLocationId] = useState("");
  const [toLocationId, setToLocationId] = useState("");
  const [productQuery, setProductQuery] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([]);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [pending, setPending] = useState<PendingTransfer[]>([]);
  const [busyTransferId, setBusyTransferId] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (!canWrite) return;
    supabase
      .from("locations")
      .select("*")
      .order("name_en")
      .then(({ data }) => setLocations(data ?? []));
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .in("type", ["raw", "processed"])
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canWrite]);

  useEffect(() => {
    if (!canWrite) return;
    let query = supabase
      .from("transfers")
      .select("*, transfer_lines(*)")
      .eq("status", "pending")
      .order("created_at", { ascending: false });
    if (!isAdmin && !isWarehouseStaff) {
      query = query.or(
        `from_location.eq.${myLocationId},to_location.eq.${myLocationId}`
      );
    }
    query.then(({ data }) => setPending((data as PendingTransfer[]) ?? []));
  }, [canWrite, isAdmin, isWarehouseStaff, myLocationId, refreshKey]);

  const productName = useMemo(() => {
    const map = new Map(products.map((p) => [p.id, p.name_en]));
    return (id: string) => map.get(id) ?? id;
  }, [products]);

  const locationName = useMemo(() => {
    const map = new Map(locations.map((l) => [l.id, l.name_en]));
    return (id: string) => map.get(id) ?? id;
  }, [locations]);

  const filteredProducts = useMemo(() => {
    const q = productQuery.trim().toLowerCase();
    if (!q) return products.slice(0, 20);
    return products
      .filter(
        (p) =>
          p.name_en.toLowerCase().includes(q) ||
          p.name_ar.includes(productQuery)
      )
      .slice(0, 20);
  }, [products, productQuery]);

  if (!canWrite) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function addLine(product: Tables<"products">) {
    setLines((prev) =>
      prev.some((l) => l.product_id === product.id)
        ? prev
        : [...prev, { product_id: product.id, name: product.name_en, qty: "1" }]
    );
    setProductQuery("");
  }

  function removeLine(productId: string) {
    setLines((prev) => prev.filter((l) => l.product_id !== productId));
  }

  function updateLineQty(productId: string, qty: string) {
    setLines((prev) =>
      prev.map((l) => (l.product_id === productId ? { ...l, qty } : l))
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

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!fromLocationId || !toLocationId) {
      setError(t.selectProductFirst);
      return;
    }
    if (fromLocationId === toLocationId) {
      setError(t.sameLocationError);
      return;
    }
    if (lines.length === 0) {
      setError(t.addLineFirst);
      return;
    }

    const parsedLines: { product_id: string; qty: number }[] = [];
    for (const line of lines) {
      const qtyNum = Number(line.qty);
      if (!Number.isFinite(qtyNum) || qtyNum <= 0) {
        setError(t.invalidQuantity);
        return;
      }
      parsedLines.push({ product_id: line.product_id, qty: qtyNum });
    }

    setSaving(true);
    const { error: rpcError } = await supabase.rpc("create_transfer", {
      p_from_location_id: fromLocationId,
      p_to_location_id: toLocationId,
      p_lines: parsedLines,
    });
    setSaving(false);

    if (rpcError) {
      console.error("Create transfer failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    setMessage(t.transferCreated);
    setFromLocationId("");
    setToLocationId("");
    setLines([]);
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
    setMessage(t.transferCompleted);
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
    setMessage(t.transferCancelled);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.transferTitle}
      </h1>

      <form onSubmit={handleSubmit} className="flex max-w-md flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm">
          {t.fromLocation}
          <select
            value={fromLocationId}
            onChange={(e) => setFromLocationId(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.fromLocation}
            </option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {l.name_en}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.toLocation}
          <select
            value={toLocationId}
            onChange={(e) => setToLocationId(e.target.value)}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="" disabled>
              {t.toLocation}
            </option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>
                {l.name_en}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.addProduct}
          <input
            type="text"
            value={productQuery}
            onChange={(e) => setProductQuery(e.target.value)}
            placeholder={t.searchProduct}
            className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
          />
          {productQuery && (
            <ul className="max-h-48 overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {filteredProducts.map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => addLine(p)}
                    className="flex h-11 w-full items-center px-3 text-start text-sm hover:bg-zinc-100 dark:hover:bg-zinc-900"
                  >
                    {p.name_en}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </label>

        {lines.length > 0 && (
          <div className="flex flex-col gap-2">
            <span className="text-sm font-medium">{t.productLines}</span>
            {lines.map((line) => (
              <div key={line.product_id} className="flex items-center gap-2">
                <span className="flex-1 text-sm">{line.name}</span>
                <input
                  type="number"
                  inputMode="decimal"
                  min="0"
                  step="any"
                  value={line.qty}
                  onChange={(e) => updateLineQty(line.product_id, e.target.value)}
                  className="h-11 w-24 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
                />
                <button
                  type="button"
                  onClick={() => removeLine(line.product_id)}
                  className="h-9 rounded-md border border-zinc-300 px-3 text-xs font-medium dark:border-zinc-700"
                >
                  {t.removeLine}
                </button>
              </div>
            ))}
          </div>
        )}

        {error && <p className="text-sm text-red-600">{error}</p>}
        {message && <p className="text-sm text-green-600">{message}</p>}

        <button
          type="submit"
          disabled={saving || !fromLocationId || !toLocationId || lines.length === 0}
          className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
        >
          {saving ? t.creatingTransfer : t.createTransfer}
        </button>
      </form>

      <section>
        <h2 className="mb-2 text-lg font-semibold">{t.pendingTransfersTitle}</h2>
        {pending.length === 0 ? (
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.noPendingTransfers}
          </p>
        ) : (
          <div className="flex flex-col gap-3">
            {pending.map((transfer) => (
              <div
                key={transfer.id}
                className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800"
              >
                <div className="mb-2 text-sm font-medium">
                  {locationName(transfer.from_location)} →{" "}
                  {locationName(transfer.to_location)}
                </div>
                <ul className="mb-2 flex flex-col gap-1 text-sm text-zinc-600 dark:text-zinc-400">
                  {transfer.transfer_lines.map((line) => (
                    <li key={line.id}>
                      {productName(line.product_id)} — {line.qty}
                    </li>
                  ))}
                </ul>
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
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

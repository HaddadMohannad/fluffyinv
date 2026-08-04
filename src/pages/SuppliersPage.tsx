import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

const emptySupplierForm = {
  id: "",
  name: "",
  phone: "",
  payment_terms: "",
  active: true,
};

export function SuppliersPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations, locationId: headerLocationId } = useActiveLocation();

  const canManageSuppliers = profile?.role === "admin";
  const canReview = profile?.role === "admin" || profile?.role === "accountant";
  const canUpload = profile?.role === "admin" || profile?.role === "branch_manager";
  const canView = canManageSuppliers || canReview || canUpload;
  const isLocationLocked = profile?.role !== "admin";

  const [suppliers, setSuppliers] = useState<Tables<"suppliers">[]>([]);
  const [invoices, setInvoices] = useState<Tables<"supplier_invoices">[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const [supplierForm, setSupplierForm] = useState(emptySupplierForm);
  const [savingSupplier, setSavingSupplier] = useState(false);

  const [uploadLocationId, setUploadLocationId] = useState("");
  const [uploadSupplierId, setUploadSupplierId] = useState("");
  const [invoiceNo, setInvoiceNo] = useState("");
  const [amount, setAmount] = useState("");
  const [dueDate, setDueDate] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);

  const [reviewNotes, setReviewNotes] = useState<Record<string, string>>({});
  const [reviewingId, setReviewingId] = useState<string | null>(null);

  useEffect(() => {
    if (!canView) return;
    supabase
      .from("suppliers")
      .select("*")
      .order("name")
      .then(({ data }) => setSuppliers(data ?? []));
  }, [canView, refreshKey]);

  useEffect(() => {
    if (!canView) return;
    supabase
      .from("supplier_invoices")
      .select("*")
      .order("created_at", { ascending: false })
      .then(({ data }) => setInvoices(data ?? []));
  }, [canView, refreshKey]);

  useEffect(() => {
    if (isLocationLocked) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- lock to the branch_manager's own location
      setUploadLocationId(profile?.location_id ?? "");
      return;
    }
    if (!uploadLocationId && headerLocationId) {
      setUploadLocationId(headerLocationId);
    }
  }, [isLocationLocked, profile?.location_id, headerLocationId, uploadLocationId]);

  const supplierName = useMemo(() => {
    const map = new Map(suppliers.map((s) => [s.id, s.name]));
    return (id: string) => map.get(id) ?? id;
  }, [suppliers]);

  const activeSuppliers = useMemo(
    () => suppliers.filter((s) => s.active),
    [suppliers]
  );

  const stats = useMemo(() => {
    const pending = invoices.filter((i) => i.status === "pending");
    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);
    const approvedThisMonth = invoices.filter(
      (i) => i.status === "approved" && new Date(i.created_at) >= monthStart
    );
    return {
      pendingCount: pending.length,
      pendingAmount: pending.reduce((sum, i) => sum + i.amount, 0),
      approvedCount: approvedThisMonth.length,
      approvedAmount: approvedThisMonth.reduce((sum, i) => sum + i.amount, 0),
      totalSuppliers: suppliers.filter((s) => s.active).length,
    };
  }, [invoices, suppliers]);

  if (!canView) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function startEditSupplier(s: Tables<"suppliers">) {
    setSupplierForm({
      id: s.id,
      name: s.name,
      phone: s.phone ?? "",
      payment_terms: s.payment_terms ?? "",
      active: s.active,
    });
  }

  async function handleSaveSupplier(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!supplierForm.name.trim()) {
      setError(t.nameRequired);
      return;
    }

    const payload = {
      name: supplierForm.name.trim(),
      phone: supplierForm.phone.trim() || null,
      payment_terms: supplierForm.payment_terms.trim() || null,
      active: supplierForm.active,
    };

    setSavingSupplier(true);
    const { error: saveError } = supplierForm.id
      ? await supabase.from("suppliers").update(payload).eq("id", supplierForm.id)
      : await supabase.from("suppliers").insert(payload);
    setSavingSupplier(false);

    if (saveError) {
      console.error("Save supplier failed:", saveError);
      setError(saveError.message);
      return;
    }

    setMessage(t.supplierSaved);
    setSupplierForm(emptySupplierForm);
    setRefreshKey((k) => k + 1);
  }

  async function handleUploadInvoice(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (!uploadLocationId || !uploadSupplierId || !file) {
      setError(t.selectProductFirst);
      return;
    }
    const amountNum = Number(amount);
    if (!Number.isFinite(amountNum) || amountNum <= 0) {
      setError(t.invalidQuantity);
      return;
    }

    setUploading(true);
    const ext = file.name.includes(".") ? file.name.split(".").pop() : "bin";
    const path = `${uploadLocationId}/${crypto.randomUUID()}.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from("invoices")
      .upload(path, file);

    if (uploadError) {
      setUploading(false);
      console.error("Upload invoice file failed:", uploadError);
      setError(uploadError.message);
      return;
    }

    const { error: insertError } = await supabase.from("supplier_invoices").insert({
      supplier_id: uploadSupplierId,
      location_id: uploadLocationId,
      invoice_no: invoiceNo.trim(),
      amount: amountNum,
      due_date: dueDate || null,
      file_path: path,
      uploaded_by: profile?.id,
    });
    setUploading(false);

    if (insertError) {
      console.error("Insert invoice failed:", insertError);
      setError(insertError.message);
      return;
    }

    setMessage(t.invoiceUploaded);
    setUploadSupplierId("");
    setInvoiceNo("");
    setAmount("");
    setDueDate("");
    setFile(null);
    setRefreshKey((k) => k + 1);
  }

  async function handleViewFile(filePath: string | null) {
    if (!filePath) return;
    const { data, error: signError } = await supabase.storage
      .from("invoices")
      .createSignedUrl(filePath, 60);
    if (signError || !data) {
      console.error("Sign invoice file URL failed:", signError);
      setError(signError?.message ?? "Could not open file.");
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function handleReview(invoiceId: string, status: "approved" | "rejected") {
    setReviewingId(invoiceId);
    setError(null);
    setMessage(null);
    const { error: rpcError } = await supabase.rpc("review_supplier_invoice", {
      p_invoice_id: invoiceId,
      p_status: status,
      p_review_note: reviewNotes[invoiceId]?.trim() || undefined,
    });
    setReviewingId(null);
    if (rpcError) {
      console.error("Review invoice failed:", rpcError);
      setError(rpcError.message);
      return;
    }
    setMessage(t.invoiceReviewed);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.suppliersTitle}
      </h1>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      <div className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.pendingInvoicesLabel}
          </p>
          <p className="text-xl font-semibold text-amber-600">
            {stats.pendingAmount.toFixed(2)} JOD
          </p>
          <p className="text-xs text-zinc-500">
            {stats.pendingCount} {t.invoicesSuffix}
          </p>
        </div>
        <div className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.approvedThisMonthLabel}
          </p>
          <p className="text-xl font-semibold text-green-600">
            {stats.approvedAmount.toFixed(2)} JOD
          </p>
          <p className="text-xs text-zinc-500">
            {stats.approvedCount} {t.invoicesSuffix}
          </p>
        </div>
        <div className="rounded-md border border-zinc-200 p-3 dark:border-zinc-800">
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {t.totalSuppliersLabel}
          </p>
          <p className="text-xl font-semibold">{stats.totalSuppliers}</p>
        </div>
      </div>

      {canUpload && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">{t.uploadInvoiceTitle}</h2>
          <form onSubmit={handleUploadInvoice} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.location}
              <select
                value={uploadLocationId}
                onChange={(e) => setUploadLocationId(e.target.value)}
                disabled={isLocationLocked}
                className="h-11 rounded-md border border-zinc-300 px-3 disabled:opacity-60 dark:border-zinc-700 dark:bg-zinc-900"
              >
                <option value="" disabled>
                  {t.location}
                </option>
                {locations.map((l) => (
                  <option key={l.id} value={l.id}>
                    {locale === "ar" ? l.name_ar : l.name_en}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.supplierLabel}
              <select
                value={uploadSupplierId}
                onChange={(e) => setUploadSupplierId(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              >
                <option value="" disabled>
                  {t.supplierLabel}
                </option>
                {activeSuppliers.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.invoiceNumberLabel}
              <input
                type="text"
                value={invoiceNo}
                onChange={(e) => setInvoiceNo(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.amountLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.dueDateLabel}
              <input
                type="date"
                value={dueDate}
                onChange={(e) => setDueDate(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.uploadFileLabel}
              <input
                type="file"
                onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                className="rounded-md border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <button
              type="submit"
              disabled={uploading}
              className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
            >
              {uploading ? t.uploadingInvoice : t.uploadInvoiceButton}
            </button>
          </form>
        </section>
      )}

      {canManageSuppliers && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">
            {supplierForm.id ? t.editSupplier : t.newSupplierTitle}
          </h2>
          <form onSubmit={handleSaveSupplier} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.supplierNameLabel}
              <input
                type="text"
                value={supplierForm.name}
                onChange={(e) =>
                  setSupplierForm({ ...supplierForm, name: e.target.value })
                }
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.supplierPhoneLabel}
              <input
                type="text"
                value={supplierForm.phone}
                onChange={(e) =>
                  setSupplierForm({ ...supplierForm, phone: e.target.value })
                }
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.paymentTermsLabel}
              <input
                type="text"
                value={supplierForm.payment_terms}
                onChange={(e) =>
                  setSupplierForm({
                    ...supplierForm,
                    payment_terms: e.target.value,
                  })
                }
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={supplierForm.active}
                onChange={(e) =>
                  setSupplierForm({ ...supplierForm, active: e.target.checked })
                }
              />
              {t.activeLabel}
            </label>
            <div className="flex gap-2">
              <button
                type="submit"
                disabled={savingSupplier}
                className="bg-fluffy-orange h-11 rounded-md px-4 text-base font-medium text-white disabled:opacity-60"
              >
                {savingSupplier ? t.savingValue : t.saveSupplier}
              </button>
              {supplierForm.id && (
                <button
                  type="button"
                  onClick={() => setSupplierForm(emptySupplierForm)}
                  className="h-11 rounded-md border border-zinc-300 px-4 text-base font-medium dark:border-zinc-700"
                >
                  {t.cancelEdit}
                </button>
              )}
            </div>
          </form>

          <div className="mt-4 overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.supplierNameLabel}</th>
                  <th className="p-2 text-start">{t.supplierPhoneLabel}</th>
                  <th className="p-2 text-center">{t.activeLabel}</th>
                  <th className="p-2" />
                </tr>
              </thead>
              <tbody>
                {suppliers.map((s) => (
                  <tr
                    key={s.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{s.name}</td>
                    <td className="p-2">{s.phone}</td>
                    <td className="p-2 text-center">{s.active ? "✓" : ""}</td>
                    <td className="p-2 text-end">
                      <button
                        type="button"
                        onClick={() => startEditSupplier(s)}
                        className="text-fluffy-orange text-sm font-medium"
                      >
                        {t.editValue}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      <section>
        <h2 className="mb-2 text-lg font-semibold">{t.invoicesTitle}</h2>
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.supplierLabel}</th>
                <th className="p-2 text-start">{t.invoiceNumberLabel}</th>
                <th className="p-2 text-end">{t.amountLabel}</th>
                <th className="p-2 text-start">{t.statusColumn}</th>
                <th className="p-2 text-start">{t.dueDateLabel}</th>
                <th className="p-2" />
                {canReview && <th className="p-2" />}
              </tr>
            </thead>
            <tbody>
              {invoices.map((inv) => (
                <tr
                  key={inv.id}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="p-2">{supplierName(inv.supplier_id)}</td>
                  <td className="p-2">{inv.invoice_no}</td>
                  <td className="p-2 text-end">{inv.amount.toFixed(2)}</td>
                  <td className="p-2">
                    <span
                      className={
                        inv.status === "approved"
                          ? "text-green-600"
                          : inv.status === "rejected"
                            ? "text-red-600"
                            : "text-amber-600"
                      }
                    >
                      {inv.status}
                    </span>
                  </td>
                  <td className="p-2">{inv.due_date ?? ""}</td>
                  <td className="p-2">
                    {inv.file_path && (
                      <button
                        type="button"
                        onClick={() => handleViewFile(inv.file_path)}
                        className="text-fluffy-orange text-sm font-medium"
                      >
                        {t.viewFileLabel}
                      </button>
                    )}
                  </td>
                  {canReview && (
                    <td className="p-2">
                      {inv.status === "pending" && (
                        <div className="flex flex-col gap-1">
                          <input
                            type="text"
                            placeholder={t.reviewNoteLabel}
                            value={reviewNotes[inv.id] ?? ""}
                            onChange={(e) =>
                              setReviewNotes((prev) => ({
                                ...prev,
                                [inv.id]: e.target.value,
                              }))
                            }
                            className="h-8 w-40 rounded-md border border-zinc-300 px-2 text-xs dark:border-zinc-700 dark:bg-zinc-900"
                          />
                          <div className="flex gap-1">
                            <button
                              type="button"
                              disabled={reviewingId === inv.id}
                              onClick={() => handleReview(inv.id, "approved")}
                              className="h-8 rounded-md bg-green-600 px-2 text-xs font-medium text-white disabled:opacity-60"
                            >
                              {t.approveInvoiceButton}
                            </button>
                            <button
                              type="button"
                              disabled={reviewingId === inv.id}
                              onClick={() => handleReview(inv.id, "rejected")}
                              className="h-8 rounded-md bg-red-600 px-2 text-xs font-medium text-white disabled:opacity-60"
                            >
                              {t.rejectInvoiceButton}
                            </button>
                          </div>
                        </div>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

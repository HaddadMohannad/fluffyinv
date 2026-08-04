import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

function today() {
  return new Date().toISOString().slice(0, 10);
}

const emptyEmployeeForm = { id: "", name: "", location_id: "", active: true };

export function CashAndExpensesPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locations, locationId: headerLocationId } = useActiveLocation();

  const canEnter = profile?.role === "admin" || profile?.role === "branch_manager";
  const canView = canEnter || profile?.role === "accountant";
  const canManageEmployees = profile?.role === "admin";
  const isLocationLocked = profile?.role !== "admin";

  const [locationId, setLocationId] = useState("");
  const [employees, setEmployees] = useState<Tables<"employees">[]>([]);
  const [expenseCategories, setExpenseCategories] = useState<
    Tables<"lookup_values">[]
  >([]);
  const [cashCounts, setCashCounts] = useState<Tables<"cash_counts">[]>([]);
  const [expenses, setExpenses] = useState<Tables<"expenses">[]>([]);
  const [transactions, setTransactions] = useState<
    Tables<"employee_cash_transactions">[]
  >([]);
  const [refreshKey, setRefreshKey] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const [countDate, setCountDate] = useState(today);
  const [countedAmount, setCountedAmount] = useState("");
  const [expectedCash, setExpectedCash] = useState<number | null>(null);
  const [savingCount, setSavingCount] = useState(false);

  const [expenseCategory, setExpenseCategory] = useState("");
  const [expenseAmount, setExpenseAmount] = useState("");
  const [expenseDescription, setExpenseDescription] = useState("");
  const [expenseDate, setExpenseDate] = useState(today);
  const [savingExpense, setSavingExpense] = useState(false);

  const [txEmployeeId, setTxEmployeeId] = useState("");
  const [txType, setTxType] = useState<"advance" | "deduction">("advance");
  const [txAmount, setTxAmount] = useState("");
  const [txNote, setTxNote] = useState("");
  const [txDate, setTxDate] = useState(today);
  const [savingTx, setSavingTx] = useState(false);

  const [employeeForm, setEmployeeForm] = useState(emptyEmployeeForm);
  const [savingEmployee, setSavingEmployee] = useState(false);

  useEffect(() => {
    if (isLocationLocked) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- lock to the branch_manager's own location
      setLocationId(profile?.location_id ?? "");
      return;
    }
    if (!locationId && headerLocationId) {
      setLocationId(headerLocationId);
    }
  }, [isLocationLocked, profile?.location_id, headerLocationId, locationId]);

  useEffect(() => {
    if (!canView) return;
    supabase
      .from("employees")
      .select("*")
      .order("name")
      .then(({ data }) => setEmployees(data ?? []));
    supabase
      .from("lookup_values")
      .select("*")
      .eq("list_key", "expense_category")
      .eq("active", true)
      .order("sort_order")
      .then(({ data }) => {
        const rows = data ?? [];
        setExpenseCategories(rows);
        setExpenseCategory((current) => current || (rows[0]?.code ?? ""));
      });
  }, [canView, refreshKey]);

  useEffect(() => {
    if (!canView || !locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when location is unset
      setCashCounts([]);
      setExpenses([]);
      setTransactions([]);
      return;
    }
    supabase
      .from("cash_counts")
      .select("*")
      .eq("location_id", locationId)
      .order("count_date", { ascending: false })
      .limit(20)
      .then(({ data }) => setCashCounts(data ?? []));
    supabase
      .from("expenses")
      .select("*")
      .eq("location_id", locationId)
      .order("expense_date", { ascending: false })
      .limit(20)
      .then(({ data }) => setExpenses(data ?? []));
    supabase
      .from("employee_cash_transactions")
      .select("*")
      .eq("location_id", locationId)
      .order("transaction_date", { ascending: false })
      .limit(20)
      .then(({ data }) => setTransactions(data ?? []));
  }, [canView, locationId, refreshKey]);

  useEffect(() => {
    if (!locationId || !countDate) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when inputs are unset
      setExpectedCash(null);
      return;
    }
    supabase
      .from("sales_orders")
      .select("net")
      .eq("location_id", locationId)
      .eq("order_date", countDate)
      .in("source", ["pos", "manual"])
      .then(({ data }) => {
        setExpectedCash((data ?? []).reduce((sum, r) => sum + r.net, 0));
      });
  }, [locationId, countDate]);

  const employeeName = useMemo(() => {
    const map = new Map(employees.map((e) => [e.id, e.name]));
    return (id: string) => map.get(id) ?? id;
  }, [employees]);

  const categoryLabel = useMemo(() => {
    const map = new Map(
      expenseCategories.map((c) => [
        c.code,
        locale === "ar" ? c.name_ar : c.name_en,
      ])
    );
    return (code: string) => map.get(code) ?? code;
  }, [expenseCategories, locale]);

  const activeEmployees = useMemo(
    () => employees.filter((e) => e.active && e.location_id === locationId),
    [employees, locationId]
  );

  if (!canView) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleSaveCount(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    const amountNum = Number(countedAmount);
    if (!Number.isFinite(amountNum) || amountNum < 0) {
      setError(t.invalidQuantity);
      return;
    }
    setSavingCount(true);
    const { error: insertError } = await supabase.from("cash_counts").insert({
      location_id: locationId,
      count_date: countDate,
      counted_amount: amountNum,
    });
    setSavingCount(false);
    if (insertError) {
      console.error("Save cash count failed:", insertError);
      setError(insertError.message);
      return;
    }
    setMessage(t.cashCountSaved);
    setCountedAmount("");
    setRefreshKey((k) => k + 1);
  }

  async function handleSaveExpense(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    const amountNum = Number(expenseAmount);
    if (!Number.isFinite(amountNum) || amountNum <= 0 || !expenseCategory) {
      setError(t.invalidQuantity);
      return;
    }
    setSavingExpense(true);
    const { error: insertError } = await supabase.from("expenses").insert({
      location_id: locationId,
      category: expenseCategory,
      amount: amountNum,
      description: expenseDescription.trim() || null,
      expense_date: expenseDate,
    });
    setSavingExpense(false);
    if (insertError) {
      console.error("Save expense failed:", insertError);
      setError(insertError.message);
      return;
    }
    setMessage(t.expenseSaved);
    setExpenseAmount("");
    setExpenseDescription("");
    setRefreshKey((k) => k + 1);
  }

  async function handleSaveTransaction(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    const amountNum = Number(txAmount);
    if (!Number.isFinite(amountNum) || amountNum <= 0 || !txEmployeeId) {
      setError(t.invalidQuantity);
      return;
    }
    setSavingTx(true);
    const { error: insertError } = await supabase
      .from("employee_cash_transactions")
      .insert({
        employee_id: txEmployeeId,
        location_id: locationId,
        type: txType,
        amount: amountNum,
        note: txNote.trim() || null,
        transaction_date: txDate,
      });
    setSavingTx(false);
    if (insertError) {
      console.error("Save employee transaction failed:", insertError);
      setError(insertError.message);
      return;
    }
    setMessage(t.transactionSaved);
    setTxAmount("");
    setTxNote("");
    setRefreshKey((k) => k + 1);
  }

  async function handleSaveEmployee(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    if (!employeeForm.name.trim() || !employeeForm.location_id) {
      setError(t.nameRequired);
      return;
    }
    setSavingEmployee(true);
    const payload = {
      name: employeeForm.name.trim(),
      location_id: employeeForm.location_id,
      active: employeeForm.active,
    };
    const { error: saveError } = employeeForm.id
      ? await supabase.from("employees").update(payload).eq("id", employeeForm.id)
      : await supabase.from("employees").insert(payload);
    setSavingEmployee(false);
    if (saveError) {
      console.error("Save employee failed:", saveError);
      setError(saveError.message);
      return;
    }
    setMessage(t.employeeSaved);
    setEmployeeForm(emptyEmployeeForm);
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
        {t.cashAndExpensesTitle}
      </h1>

      <label className="flex max-w-md flex-col gap-1 text-sm">
        {t.location}
        <select
          value={locationId}
          onChange={(e) => setLocationId(e.target.value)}
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

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      {canEnter && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">{t.cashCountTitle}</h2>
          <form onSubmit={handleSaveCount} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.closeDateLabel}
              <input
                type="date"
                value={countDate}
                onChange={(e) => setCountDate(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            {expectedCash !== null && (
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                {t.expectedCashLabel}: {expectedCash.toFixed(2)} JOD
              </p>
            )}
            <label className="flex flex-col gap-1 text-sm">
              {t.countedAmountLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={countedAmount}
                onChange={(e) => setCountedAmount(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <button
              type="submit"
              disabled={savingCount || !locationId}
              className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
            >
              {savingCount ? t.submitting : t.submitEntry}
            </button>
          </form>

          <div className="mt-3 overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.closeDateLabel}</th>
                  <th className="p-2 text-end">{t.countedAmountLabel}</th>
                </tr>
              </thead>
              <tbody>
                {cashCounts.map((c) => (
                  <tr
                    key={c.count_date}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{c.count_date}</td>
                    <td className="p-2 text-end">
                      {c.counted_amount.toFixed(2)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {canEnter && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">{t.expensesTitle}</h2>
          <form onSubmit={handleSaveExpense} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.expenseCategoryLabel}
              <select
                value={expenseCategory}
                onChange={(e) => setExpenseCategory(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              >
                {expenseCategories.map((c) => (
                  <option key={c.code} value={c.code}>
                    {locale === "ar" ? c.name_ar : c.name_en}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.amountLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={expenseAmount}
                onChange={(e) => setExpenseAmount(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.note}
              <input
                type="text"
                value={expenseDescription}
                onChange={(e) => setExpenseDescription(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.closeDateLabel}
              <input
                type="date"
                value={expenseDate}
                onChange={(e) => setExpenseDate(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <button
              type="submit"
              disabled={savingExpense || !locationId}
              className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
            >
              {savingExpense ? t.submitting : t.submitEntry}
            </button>
          </form>

          <div className="mt-3 overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.expenseCategoryLabel}</th>
                  <th className="p-2 text-end">{t.amountLabel}</th>
                  <th className="p-2 text-start">{t.closeDateLabel}</th>
                </tr>
              </thead>
              <tbody>
                {expenses.map((ex) => (
                  <tr
                    key={ex.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{categoryLabel(ex.category)}</td>
                    <td className="p-2 text-end">{ex.amount.toFixed(2)}</td>
                    <td className="p-2">{ex.expense_date}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {canEnter && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">
            {t.employeeTransactionsTitle}
          </h2>
          <form onSubmit={handleSaveTransaction} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.employeeLabel}
              <select
                value={txEmployeeId}
                onChange={(e) => setTxEmployeeId(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              >
                <option value="" disabled>
                  {t.employeeLabel}
                </option>
                {activeEmployees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.transactionTypeLabel}
              <select
                value={txType}
                onChange={(e) =>
                  setTxType(e.target.value as "advance" | "deduction")
                }
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              >
                <option value="advance">{t.advanceLabel}</option>
                <option value="deduction">{t.deductionLabel}</option>
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.amountLabel}
              <input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={txAmount}
                onChange={(e) => setTxAmount(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.note}
              <input
                type="text"
                value={txNote}
                onChange={(e) => setTxNote(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.closeDateLabel}
              <input
                type="date"
                value={txDate}
                onChange={(e) => setTxDate(e.target.value)}
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <button
              type="submit"
              disabled={savingTx || !locationId}
              className="bg-fluffy-orange h-11 rounded-md text-base font-medium text-white disabled:opacity-60"
            >
              {savingTx ? t.submitting : t.submitEntry}
            </button>
          </form>

          <div className="mt-3 overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
            <table className="w-full min-w-max text-sm">
              <thead className="bg-zinc-50 dark:bg-zinc-900">
                <tr>
                  <th className="p-2 text-start">{t.employeeLabel}</th>
                  <th className="p-2 text-start">{t.transactionTypeLabel}</th>
                  <th className="p-2 text-end">{t.amountLabel}</th>
                  <th className="p-2 text-start">{t.closeDateLabel}</th>
                </tr>
              </thead>
              <tbody>
                {transactions.map((tx) => (
                  <tr
                    key={tx.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{employeeName(tx.employee_id)}</td>
                    <td className="p-2">
                      {tx.type === "advance" ? t.advanceLabel : t.deductionLabel}
                    </td>
                    <td className="p-2 text-end">{tx.amount.toFixed(2)}</td>
                    <td className="p-2">{tx.transaction_date}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {canManageEmployees && (
        <section className="max-w-md">
          <h2 className="mb-2 text-lg font-semibold">
            {employeeForm.id ? t.editEmployee : t.newEmployeeTitle}
          </h2>
          <form onSubmit={handleSaveEmployee} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              {t.employeeNameLabel}
              <input
                type="text"
                value={employeeForm.name}
                onChange={(e) =>
                  setEmployeeForm({ ...employeeForm, name: e.target.value })
                }
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.location}
              <select
                value={employeeForm.location_id}
                onChange={(e) =>
                  setEmployeeForm({
                    ...employeeForm,
                    location_id: e.target.value,
                  })
                }
                className="h-11 rounded-md border border-zinc-300 px-3 dark:border-zinc-700 dark:bg-zinc-900"
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
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={employeeForm.active}
                onChange={(e) =>
                  setEmployeeForm({ ...employeeForm, active: e.target.checked })
                }
              />
              {t.activeLabel}
            </label>
            <div className="flex gap-2">
              <button
                type="submit"
                disabled={savingEmployee}
                className="bg-fluffy-orange h-11 rounded-md px-4 text-base font-medium text-white disabled:opacity-60"
              >
                {savingEmployee ? t.savingValue : t.saveEmployee}
              </button>
              {employeeForm.id && (
                <button
                  type="button"
                  onClick={() => setEmployeeForm(emptyEmployeeForm)}
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
                  <th className="p-2 text-start">{t.employeeNameLabel}</th>
                  <th className="p-2 text-start">{t.location}</th>
                  <th className="p-2 text-center">{t.activeLabel}</th>
                  <th className="p-2" />
                </tr>
              </thead>
              <tbody>
                {employees.map((emp) => (
                  <tr
                    key={emp.id}
                    className="border-t border-zinc-100 dark:border-zinc-800"
                  >
                    <td className="p-2">{emp.name}</td>
                    <td className="p-2">
                      {locations.find((l) => l.id === emp.location_id)
                        ? locale === "ar"
                          ? locations.find((l) => l.id === emp.location_id)!.name_ar
                          : locations.find((l) => l.id === emp.location_id)!.name_en
                        : emp.location_id}
                    </td>
                    <td className="p-2 text-center">{emp.active ? "✓" : ""}</td>
                    <td className="p-2 text-end">
                      <button
                        type="button"
                        onClick={() =>
                          setEmployeeForm({
                            id: emp.id,
                            name: emp.name,
                            location_id: emp.location_id,
                            active: emp.active,
                          })
                        }
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
    </div>
  );
}

import { useCallback, useEffect, useMemo, useState } from "react";
import { Package, Plus } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";
import { WasteQuickModal } from "@/components/quick-actions/WasteQuickModal";
import { HospitalityQuickModal } from "@/components/quick-actions/HospitalityQuickModal";
import { TransferQuickModal } from "@/components/quick-actions/TransferQuickModal";
import { AddWasteModal } from "@/components/quick-actions/AddWasteModal";
import { AddHospitalityModal } from "@/components/quick-actions/AddHospitalityModal";
import { TransferStockModal } from "@/components/quick-actions/TransferStockModal";
import { AddProductModal } from "@/components/quick-actions/AddProductModal";
import { Pill } from "@/components/Pill";
import { categoryTone } from "@/lib/pillColors";

type QuickAction = "waste" | "hospitality" | "transfer";
type GlobalAction = "waste" | "hospitality" | "transfer" | "product";

export function InventoryPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();
  const { locationId } = useActiveLocation();

  const canView =
    profile?.role === "admin" ||
    profile?.role === "branch_manager" ||
    profile?.role === "warehouse_staff";
  const canWasteOrHospitality =
    profile?.role === "admin" || profile?.role === "branch_manager";
  const isAdmin = profile?.role === "admin";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [stock, setStock] = useState<Record<string, number>>({});
  const [refreshKey, setRefreshKey] = useState(0);
  const [activeModal, setActiveModal] = useState<{
    action: QuickAction;
    product: Tables<"products">;
  } | null>(null);
  const [activeGlobalModal, setActiveGlobalModal] =
    useState<GlobalAction | null>(null);
  const [reorderEdits, setReorderEdits] = useState<Record<string, string>>({});

  const fetchProducts = useCallback(() => {
    if (!canView) return;
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [canView]);

  useEffect(() => {
    fetchProducts();
  }, [fetchProducts]);

  useEffect(() => {
    if (!locationId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when location is unset
      setStock({});
      return;
    }
    supabase
      .from("v_current_stock")
      .select("product_id, qty")
      .eq("location_id", locationId)
      .then(({ data }) => {
        const map: Record<string, number> = {};
        for (const row of data ?? []) {
          if (row.product_id !== null && row.qty !== null) {
            map[row.product_id] = row.qty;
          }
        }
        setStock(map);
      });
  }, [locationId, refreshKey]);

  const categoryLabel = useMemo(() => {
    const labels: Record<Tables<"products">["type"], string> = {
      raw: t.categoryRaw,
      processed: t.categoryProcessed,
      sellable: t.categorySellable,
    };
    return (type: Tables<"products">["type"]) => labels[type];
  }, [t]);

  if (!canView) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  function closeModal() {
    setActiveModal(null);
  }

  function handleSaved() {
    setRefreshKey((k) => k + 1);
  }

  function reorderValue(product: Tables<"products">) {
    return product.id in reorderEdits
      ? reorderEdits[product.id]
      : (product.reorder_threshold?.toString() ?? "");
  }

  async function handleSaveReorderThreshold(product: Tables<"products">) {
    const raw = reorderValue(product).trim();
    const parsed = raw === "" ? null : Number(raw);
    if (parsed !== null && !Number.isFinite(parsed)) return;
    if (parsed === (product.reorder_threshold ?? null)) return;

    const { error: updateError } = await supabase
      .from("products")
      .update({ reorder_threshold: parsed })
      .eq("id", product.id);
    if (updateError) {
      console.error("Save reorder threshold failed:", updateError);
      return;
    }
    setProducts((prev) =>
      prev.map((p) =>
        p.id === product.id ? { ...p, reorder_threshold: parsed } : p
      )
    );
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.inventoryTitle}
        </h1>
        <div className="flex flex-wrap gap-2">
          {canWasteOrHospitality && (
            <button
              type="button"
              onClick={() => setActiveGlobalModal("waste")}
              className="h-9 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
            >
              {t.addWasteAction}
            </button>
          )}
          {canWasteOrHospitality && (
            <button
              type="button"
              onClick={() => setActiveGlobalModal("hospitality")}
              className="h-9 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
            >
              {t.addHospitalityAction}
            </button>
          )}
          <button
            type="button"
            onClick={() => setActiveGlobalModal("transfer")}
            className="h-9 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
          >
            {t.transferStockAction}
          </button>
          {isAdmin && (
            <button
              type="button"
              onClick={() => setActiveGlobalModal("product")}
              className="bg-fluffy-orange flex h-9 items-center gap-1 rounded-md px-3 text-sm font-medium text-white"
            >
              <Plus className="h-4 w-4" />
              {t.addProductAction}
            </button>
          )}
        </div>
      </div>

      {!locationId ? (
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          {t.noInventoryItems}
        </p>
      ) : (
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.product}</th>
                <th className="p-2 text-start">{t.categoryColumn}</th>
                <th className="p-2 text-end">{t.quantity}</th>
                <th className="p-2 text-end">{t.unitCost}</th>
                <th className="p-2 text-end">{t.totalValueColumn}</th>
                {isAdmin && (
                  <th className="p-2 text-end">{t.reorderThresholdColumn}</th>
                )}
                <th className="p-2" />
              </tr>
            </thead>
            <tbody>
              {products.length === 0 ? (
                <tr>
                  <td
                    colSpan={isAdmin ? 7 : 6}
                    className="p-6 text-center text-zinc-500 dark:text-zinc-400"
                  >
                    <div className="flex flex-col items-center gap-2">
                      <Package className="h-6 w-6" />
                      {t.noInventoryItems}
                    </div>
                  </td>
                </tr>
              ) : (
                products.map((product) => {
                  const qty = stock[product.id] ?? 0;
                  const totalValue = qty * (product.avg_cost ?? 0);
                  return (
                    <tr
                      key={product.id}
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="p-2">
                        {locale === "ar" ? product.name_ar : product.name_en}
                      </td>
                      <td className="p-2">
                        <Pill tone={categoryTone(product.type)}>
                          {categoryLabel(product.type)}
                        </Pill>
                      </td>
                      <td className="p-2 text-end">{qty}</td>
                      <td className="p-2 text-end">
                        {(product.avg_cost ?? 0).toFixed(3)}
                      </td>
                      <td className="p-2 text-end">{totalValue.toFixed(3)}</td>
                      {isAdmin && (
                        <td className="p-2 text-end">
                          <input
                            type="number"
                            inputMode="decimal"
                            min="0"
                            step="any"
                            value={reorderValue(product)}
                            onChange={(e) =>
                              setReorderEdits((prev) => ({
                                ...prev,
                                [product.id]: e.target.value,
                              }))
                            }
                            onBlur={() => handleSaveReorderThreshold(product)}
                            className="h-8 w-20 rounded-md border border-zinc-300 px-2 text-end dark:border-zinc-700 dark:bg-zinc-900"
                          />
                        </td>
                      )}
                      <td className="p-2 text-end">
                        <div className="flex justify-end gap-1">
                          {canWasteOrHospitality && (
                            <button
                              type="button"
                              onClick={() =>
                                setActiveModal({ action: "waste", product })
                              }
                              className="h-8 rounded-md border border-zinc-300 px-2 text-xs font-medium dark:border-zinc-700"
                            >
                              {t.addWasteAction}
                            </button>
                          )}
                          {canWasteOrHospitality && (
                            <button
                              type="button"
                              onClick={() =>
                                setActiveModal({
                                  action: "hospitality",
                                  product,
                                })
                              }
                              className="h-8 rounded-md border border-zinc-300 px-2 text-xs font-medium dark:border-zinc-700"
                            >
                              {t.addHospitalityAction}
                            </button>
                          )}
                          <button
                            type="button"
                            onClick={() =>
                              setActiveModal({ action: "transfer", product })
                            }
                            className="h-8 rounded-md border border-zinc-300 px-2 text-xs font-medium dark:border-zinc-700"
                          >
                            {t.transferAction}
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      )}

      {activeModal?.action === "waste" && (
        <WasteQuickModal
          locationId={locationId}
          product={activeModal.product}
          onClose={closeModal}
          onSaved={handleSaved}
        />
      )}
      {activeModal?.action === "hospitality" && (
        <HospitalityQuickModal
          locationId={locationId}
          product={activeModal.product}
          onClose={closeModal}
          onSaved={handleSaved}
        />
      )}
      {activeModal?.action === "transfer" && (
        <TransferQuickModal
          locationId={locationId}
          product={activeModal.product}
          onClose={closeModal}
          onSaved={handleSaved}
        />
      )}

      {activeGlobalModal === "waste" && (
        <AddWasteModal
          locationId={locationId}
          onClose={() => setActiveGlobalModal(null)}
          onSaved={handleSaved}
        />
      )}
      {activeGlobalModal === "hospitality" && (
        <AddHospitalityModal
          locationId={locationId}
          onClose={() => setActiveGlobalModal(null)}
          onSaved={handleSaved}
        />
      )}
      {activeGlobalModal === "transfer" && (
        <TransferStockModal
          locationId={locationId}
          onClose={() => setActiveGlobalModal(null)}
          onSaved={handleSaved}
        />
      )}
      {activeGlobalModal === "product" && (
        <AddProductModal
          onClose={() => setActiveGlobalModal(null)}
          onSaved={fetchProducts}
        />
      )}
    </div>
  );
}

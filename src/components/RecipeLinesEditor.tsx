import { useEffect, useState } from "react";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type RecipeLine = Tables<"recipe_lines"> & {
  component: Pick<
    Tables<"products">,
    "id" | "name_en" | "name_ar" | "recipe_unit" | "storage_to_recipe_factor"
  > | null;
};

export function RecipeLinesEditor({
  parentProductId,
}: {
  parentProductId: string;
}) {
  const { t, locale } = useLocale();

  const [lines, setLines] = useState<RecipeLine[]>([]);
  const [candidates, setCandidates] = useState<Tables<"products">[]>([]);
  const [componentId, setComponentId] = useState("");
  const [qty, setQty] = useState("");
  const [newUnit, setNewUnit] = useState("");
  const [newFactor, setNewFactor] = useState("1");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    supabase
      .from("products")
      .select("*")
      .eq("active", true)
      .neq("id", parentProductId)
      .order("name_en")
      .then(({ data }) => setCandidates(data ?? []));
  }, [parentProductId]);

  useEffect(() => {
    supabase
      .from("recipe_lines")
      .select(
        "*, component:component_product_id(id, name_en, name_ar, recipe_unit, storage_to_recipe_factor)"
      )
      .eq("parent_product_id", parentProductId)
      .then(({ data }) => setLines((data ?? []) as RecipeLine[]));
  }, [parentProductId, refreshKey]);

  const selectedComponent = candidates.find((c) => c.id === componentId);
  const needsUnit = selectedComponent && !selectedComponent.recipe_unit;

  function productName(p: { name_en: string; name_ar: string } | null) {
    if (!p) return "";
    return locale === "ar" ? p.name_ar : p.name_en;
  }

  async function handleAdd() {
    setError(null);
    const qtyNum = Number(qty);
    if (!componentId || !Number.isFinite(qtyNum) || qtyNum <= 0) {
      setError(t.invalidQuantity);
      return;
    }

    setSaving(true);

    if (needsUnit) {
      const factorNum = Number(newFactor);
      if (!newUnit.trim() || !Number.isFinite(factorNum) || factorNum <= 0) {
        setError(t.recipeUnitRequired);
        setSaving(false);
        return;
      }
      const { error: unitError } = await supabase
        .from("products")
        .update({
          recipe_unit: newUnit.trim(),
          storage_to_recipe_factor: factorNum,
        })
        .eq("id", componentId);
      if (unitError) {
        console.error("Set recipe unit failed:", unitError);
        setError(unitError.message);
        setSaving(false);
        return;
      }
    }

    const { error: insertError } = await supabase.from("recipe_lines").insert({
      parent_product_id: parentProductId,
      component_product_id: componentId,
      qty_per_unit: qtyNum,
    });
    setSaving(false);

    if (insertError) {
      console.error("Add recipe line failed:", insertError);
      setError(insertError.message);
      return;
    }

    setComponentId("");
    setQty("");
    setNewUnit("");
    setNewFactor("1");
    setRefreshKey((k) => k + 1);
  }

  async function handleRemove(lineId: string) {
    setError(null);
    const { error: deleteError } = await supabase
      .from("recipe_lines")
      .delete()
      .eq("id", lineId);
    if (deleteError) {
      console.error("Remove recipe line failed:", deleteError);
      setError(deleteError.message);
      return;
    }
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-col gap-3">
      {error && <p className="text-sm text-red-600">{error}</p>}

      {lines.length === 0 ? (
        <p className="text-sm text-zinc-500 dark:text-zinc-400">
          {t.noRecipeLines}
        </p>
      ) : (
        <div className="flex flex-col gap-2">
          {lines.map((line) => (
            <div
              key={line.id}
              className="flex items-center justify-between rounded-md border border-zinc-200 p-2 text-sm dark:border-zinc-800"
            >
              <span>{productName(line.component)}</span>
              <div className="flex items-center gap-3">
                <span className="text-zinc-600 dark:text-zinc-400">
                  {line.qty_per_unit} {line.component?.recipe_unit ?? ""}
                </span>
                <button
                  type="button"
                  onClick={() => handleRemove(line.id)}
                  className="text-xs font-medium text-red-600"
                >
                  {t.removeLine}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="flex flex-wrap items-end gap-2">
        <label className="flex flex-col gap-1 text-sm">
          {t.recipeComponentLabel}
          <select
            value={componentId}
            onChange={(e) => setComponentId(e.target.value)}
            className="h-10 min-w-48 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
          >
            <option value="">{t.selectProductFirst}</option>
            {candidates.map((c) => (
              <option key={c.id} value={c.id}>
                {productName(c)}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm">
          {t.recipeQtyLabel}
          {selectedComponent?.recipe_unit
            ? ` (${selectedComponent.recipe_unit})`
            : ""}
          <input
            type="number"
            inputMode="decimal"
            step="any"
            min="0"
            value={qty}
            onChange={(e) => setQty(e.target.value)}
            className="h-10 w-28 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
          />
        </label>

        {needsUnit && (
          <>
            <label className="flex flex-col gap-1 text-sm">
              {t.recipeUnitLabel}
              <input
                type="text"
                dir="auto"
                placeholder={t.recipeUnitPlaceholder}
                value={newUnit}
                onChange={(e) => setNewUnit(e.target.value)}
                className="h-10 w-32 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              {t.recipeFactorLabel}
              <input
                type="number"
                inputMode="decimal"
                step="any"
                min="0"
                value={newFactor}
                onChange={(e) => setNewFactor(e.target.value)}
                className="h-10 w-24 rounded-md border border-zinc-300 px-2 dark:border-zinc-700 dark:bg-zinc-900"
              />
            </label>
          </>
        )}

        <button
          type="button"
          onClick={handleAdd}
          disabled={saving || !componentId}
          className="bg-fluffy-orange h-10 rounded-md px-3 text-sm font-medium text-white disabled:opacity-60"
        >
          {saving ? t.savingValue : t.addRecipeLine}
        </button>
      </div>
    </div>
  );
}

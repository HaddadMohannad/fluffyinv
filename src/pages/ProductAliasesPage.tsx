import { useEffect, useMemo, useState } from "react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { supabase } from "@/lib/supabase/client";
import type { Tables } from "@/lib/supabase/database.types";

type UnmatchedGroup = {
  rawName: string;
  occurrences: number;
  totalQty: number;
};

export function ProductAliasesPage() {
  const { profile } = useAuth();
  const { t, locale } = useLocale();

  const isAdmin = profile?.role === "admin";

  const [products, setProducts] = useState<Tables<"products">[]>([]);
  const [groups, setGroups] = useState<UnmatchedGroup[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);
  const [activeRawName, setActiveRawName] = useState<string | null>(null);
  const [productQuery, setProductQuery] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!isAdmin) return;
    supabase
      .from("products")
      .select("*")
      .order("name_en")
      .then(({ data }) => setProducts(data ?? []));
  }, [isAdmin]);

  useEffect(() => {
    if (!isAdmin) return;
    supabase
      .from("sales_lines")
      .select("raw_item_name, qty")
      .is("product_id", null)
      .then(({ data }) => {
        const map = new Map<string, UnmatchedGroup>();
        for (const row of data ?? []) {
          const rawName = row.raw_item_name ?? "";
          if (!rawName) continue;
          const existing = map.get(rawName);
          if (existing) {
            existing.occurrences += 1;
            existing.totalQty += row.qty;
          } else {
            map.set(rawName, { rawName, occurrences: 1, totalQty: row.qty });
          }
        }
        setGroups(
          Array.from(map.values()).sort((a, b) => b.occurrences - a.occurrences)
        );
      });
  }, [isAdmin, refreshKey]);

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

  if (!isAdmin) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-center text-sm text-zinc-600 dark:text-zinc-400">
        {t.notPermitted}
      </div>
    );
  }

  async function handleMap(rawName: string, productId: string) {
    setSaving(true);
    setError(null);
    setMessage(null);
    const { data, error: rpcError } = await supabase.rpc(
      "apply_product_alias",
      { p_raw_name: rawName, p_product_id: productId }
    );
    setSaving(false);

    if (rpcError) {
      console.error("Apply product alias failed:", rpcError);
      setError(rpcError.message);
      return;
    }

    setMessage(`${t.aliasAppliedPrefix} ${data ?? 0} ${t.aliasAppliedSuffix}`);
    setActiveRawName(null);
    setProductQuery("");
    setRefreshKey((k) => k + 1);
  }

  return (
    <div className="flex flex-1 flex-col gap-6 p-6">
      <div>
        <h1 className="text-fluffy-dark text-2xl font-semibold dark:text-zinc-50">
          {t.unmatchedItemsTitle}
        </h1>
        <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
          {t.unmatchedItemsSubtitle}
        </p>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-green-600">{message}</p>}

      {groups.length === 0 ? (
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          {t.noUnmatchedItems}
        </p>
      ) : (
        <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-max text-sm">
            <thead className="bg-zinc-50 dark:bg-zinc-900">
              <tr>
                <th className="p-2 text-start">{t.product}</th>
                <th className="p-2 text-end">{t.occurrencesColumn}</th>
                <th className="p-2 text-end">{t.totalQtyColumn}</th>
                <th className="p-2 text-start">{t.mapToProductAction}</th>
              </tr>
            </thead>
            <tbody>
              {groups.map((group) => (
                <tr
                  key={group.rawName}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="p-2">{group.rawName}</td>
                  <td className="p-2 text-end">{group.occurrences}</td>
                  <td className="p-2 text-end">{group.totalQty}</td>
                  <td className="p-2">
                    {activeRawName === group.rawName ? (
                      <div className="relative max-w-xs">
                        <input
                          type="text"
                          autoFocus
                          disabled={saving}
                          value={productQuery}
                          onChange={(e) => setProductQuery(e.target.value)}
                          placeholder={t.searchProduct}
                          className="h-9 w-full rounded-md border border-zinc-300 px-3 text-sm dark:border-zinc-700 dark:bg-zinc-900"
                        />
                        {productQuery && (
                          <ul className="absolute z-10 max-h-48 w-full overflow-y-auto rounded-md border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900">
                            {filteredProducts.map((p) => (
                              <li key={p.id}>
                                <button
                                  type="button"
                                  onClick={() => handleMap(group.rawName, p.id)}
                                  className="flex h-9 w-full items-center px-3 text-start text-sm hover:bg-zinc-100 dark:hover:bg-zinc-800"
                                >
                                  {locale === "ar" ? p.name_ar : p.name_en}
                                </button>
                              </li>
                            ))}
                          </ul>
                        )}
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={() => {
                          setActiveRawName(group.rawName);
                          setProductQuery("");
                        }}
                        className="h-9 rounded-md border border-zinc-300 px-3 text-xs font-medium dark:border-zinc-700"
                      >
                        {t.mapToProductAction}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

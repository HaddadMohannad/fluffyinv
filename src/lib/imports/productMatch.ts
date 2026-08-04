import type { Tables } from "@/lib/supabase/database.types";

// Words Talabat appends as a bracketed choice that names a distinct SKU
// (Meal vs Sandwich, pizza size) or is just a prep preference with no
// separate SKU (spice level, "Mix"). Trying the bare name (and, for
// pizzas, the first-letter-abbreviated size the catalog actually uses --
// "Alfredo Pizza S" not "Alfredo Pizza Small") as extra candidates lets a
// single product/alias row cover every variant without guessing which
// case applies; a wrong candidate simply fails to match anything.
const VARIANT_WORDS = new Set([
  "Meal",
  "Sandwich",
  "Small",
  "Medium",
  "Large",
  "Normal",
  "Spicy",
  "Mix",
]);

function normalize(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, " ");
}

function candidateNames(itemName: string): string[] {
  const words = itemName.split(" ");
  const last = words[words.length - 1];
  if (words.length > 1 && VARIANT_WORDS.has(last)) {
    const base = words.slice(0, -1).join(" ");
    return [itemName, base, `${base} ${last[0].toUpperCase()}`];
  }
  return [itemName];
}

export type ProductLookup = {
  byName: Map<string, string>;
  byAlias: Map<string, string>;
};

export function buildProductLookup(
  products: Pick<Tables<"products">, "id" | "name_en" | "name_ar">[],
  aliases: Pick<Tables<"product_aliases">, "raw_name" | "product_id">[]
): ProductLookup {
  const byName = new Map<string, string>();
  for (const p of products) {
    byName.set(normalize(p.name_en), p.id);
    byName.set(normalize(p.name_ar), p.id);
  }
  const byAlias = new Map<string, string>();
  for (const a of aliases) {
    byAlias.set(normalize(a.raw_name), a.product_id);
  }
  return { byName, byAlias };
}

/** Resolves a clean item name (see `NormalizedOrderLine.itemName`) to a
 * product id, trying the exact catalog name first, then any admin-
 * confirmed alias. Returns null (never guesses) when nothing matches. */
export function resolveProductId(
  itemName: string,
  lookup: ProductLookup
): string | null {
  for (const candidate of candidateNames(itemName)) {
    const key = normalize(candidate);
    const direct = lookup.byName.get(key);
    if (direct) return direct;
    const aliased = lookup.byAlias.get(key);
    if (aliased) return aliased;
  }
  return null;
}

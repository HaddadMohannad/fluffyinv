import { supabase } from "@/lib/supabase/client";
import { buildProductLookup, resolveProductId } from "./productMatch";
import type { ImportSource, NormalizedOrder } from "./types";

const CHUNK_SIZE = 500;

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

export type ImportRunResult = {
  importFileId: string;
  totalNormalized: number;
  resolvedCount: number;
  unresolvedCount: number;
  insertedCount: number;
  lineMatchedCount: number;
  lineUnmatchedCount: number;
};

export async function importOrders({
  source,
  filename,
  orders,
  uploadedBy,
}: {
  source: ImportSource;
  filename: string;
  orders: NormalizedOrder[];
  uploadedBy: string;
}): Promise<ImportRunResult> {
  const { data: aliases, error: aliasError } = await supabase
    .from("location_aliases")
    .select("source_name, location_id, brand")
    .eq("source", source);

  if (aliasError) throw aliasError;

  const aliasMap = new Map((aliases ?? []).map((a) => [a.source_name, a]));

  const { data: products, error: productsError } = await supabase
    .from("products")
    .select("id, name_en, name_ar");
  if (productsError) throw productsError;

  const { data: productAliases, error: productAliasError } = await supabase
    .from("product_aliases")
    .select("raw_name, product_id");
  if (productAliasError) throw productAliasError;

  const productLookup = buildProductLookup(products ?? [], productAliases ?? []);

  const resolved: (NormalizedOrder & {
    location_id: string;
    brand: string | null;
  })[] = [];
  const unresolved: NormalizedOrder[] = [];

  for (const order of orders) {
    const alias = aliasMap.get(order.branchName);
    if (alias) {
      resolved.push({
        ...order,
        location_id: alias.location_id,
        brand: alias.brand,
      });
    } else {
      unresolved.push(order);
    }
  }

  const { data: importFile, error: importFileError } = await supabase
    .from("import_files")
    .insert({
      source,
      filename,
      row_count: orders.length,
      uploaded_by: uploadedBy,
    })
    .select("id")
    .single();

  if (importFileError || !importFile) {
    throw importFileError ?? new Error("Failed to create import_files row");
  }

  const importFileId = importFile.id;

  for (const batch of chunk(unresolved, CHUNK_SIZE)) {
    const { error } = await supabase.from("import_rejects").insert(
      batch.map((order) => ({
        import_file_id: importFileId,
        raw_row: order,
        reason: `No location_alias found for branch name "${order.branchName}" (source: ${source})`,
      }))
    );
    if (error) throw error;
  }

  let insertedCount = 0;
  let lineMatchedCount = 0;
  let lineUnmatchedCount = 0;

  for (const batch of chunk(resolved, CHUNK_SIZE)) {
    const { data: upserted, error: upsertError } = await supabase
      .from("sales_orders")
      .upsert(
        batch.map((order) => ({
          source,
          external_ref: order.externalRef,
          location_id: order.location_id,
          brand: order.brand,
          order_date: order.orderDate,
          gross: order.gross,
          commission: order.commission,
          net: order.net,
          import_file_id: importFileId,
        })),
        { onConflict: "source,external_ref", ignoreDuplicates: true }
      )
      .select("id");

    if (upsertError) throw upsertError;
    insertedCount += upserted?.length ?? 0;

    // `upsert` + `ignoreDuplicates` only returns rows it actually inserted,
    // so a re-import of already-existing orders (e.g. backfilling line
    // items onto orders from a prior import run) needs a fresh lookup to
    // get every order's id, not just the newly-inserted ones.
    const ordersWithLines = batch.filter(
      (order) => order.lines !== undefined
    );
    if (ordersWithLines.length === 0) continue;

    const { data: orderIdRows, error: lookupError } = await supabase
      .from("sales_orders")
      .select("id, external_ref")
      .eq("source", source)
      .in(
        "external_ref",
        ordersWithLines.map((o) => o.externalRef)
      );
    if (lookupError) throw lookupError;

    const orderIdByRef = new Map(
      (orderIdRows ?? []).map((r) => [r.external_ref, r.id])
    );

    const linesBatch = ordersWithLines
      .map((order) => {
        const orderId = orderIdByRef.get(order.externalRef);
        if (!orderId) return null;
        const lines = (order.lines ?? []).map((line) => {
          const productId = resolveProductId(line.itemName, productLookup);
          if (productId) lineMatchedCount += 1;
          else lineUnmatchedCount += 1;
          return {
            product_id: productId,
            qty: line.qty,
            raw_item_name: line.itemName,
          };
        });
        return { order_id: orderId, lines };
      })
      .filter((entry): entry is NonNullable<typeof entry> => entry !== null);

    if (linesBatch.length > 0) {
      const { error: linesError } = await supabase.rpc("replace_sales_lines", {
        p_batch: linesBatch,
      });
      if (linesError) throw linesError;
    }
  }

  return {
    importFileId,
    totalNormalized: orders.length,
    resolvedCount: resolved.length,
    unresolvedCount: unresolved.length,
    insertedCount,
    lineMatchedCount,
    lineUnmatchedCount,
  };
}

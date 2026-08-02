import { supabase } from "@/lib/supabase/client";
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
  for (const batch of chunk(resolved, CHUNK_SIZE)) {
    const { data, error } = await supabase
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

    if (error) throw error;
    insertedCount += data?.length ?? 0;
  }

  return {
    importFileId,
    totalNormalized: orders.length,
    resolvedCount: resolved.length,
    unresolvedCount: unresolved.length,
    insertedCount,
  };
}

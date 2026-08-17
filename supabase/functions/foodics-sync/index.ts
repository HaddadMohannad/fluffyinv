// FLU-12: pulls closed orders directly from the Foodics API (Foodics is a
// POS, not a CSV-export marketplace like Talabat/Careem, so this mirrors
// the shape of src/lib/imports/*.ts -- NormalizedOrder-equivalent rows
// upserted into sales_orders/sales_lines -- but sources rows from a live
// API call instead of a parsed file). Manually triggered from the Import
// page by an admin/accountant; no scheduler wired up yet (FLU-12 MVP).
//
// Two modes, both idempotent (safe to re-run/overlap):
//  - Incremental (no request body, or body without `from`): picks up from
//    the most recent already-synced order (minus a 1-day buffer), or the
//    last DEFAULT_LOOKBACK_DAYS days on a cold start. This is what the
//    "Sync Foodics now" button in the app calls.
//  - Chunked backfill (POST body `{"from":"YYYY-MM-DD","to":"YYYY-MM-DD"}`):
//    pulls a specific date window regardless of what's already synced. For
//    backfilling historical data, invoke this repeatedly with small
//    windows (a week or less) -- a wide window risks exceeding the Edge
//    Function's execution time limit given ~200 orders/page with full
//    branch+product includes. Not wired into any UI yet; invoke directly
//    (e.g. via the Supabase dashboard's function testing UI, or a small
//    script looping over date ranges) once FOODICS_API_TOKEN is set.
//
// Requires a `FOODICS_API_TOKEN` secret (Foodics personal access token,
// generated in Foodics Back Office / developers.foodics.com). The
// business_date_after/business_date_before/status/include/page query
// params below mirror the Foodics MCP tool's schema, which is presumably a
// thin pass-through of the real v5 API -- verify against
// https://developers.foodics.com once a token is available for a live
// test run, since we could not exercise the raw HTTP endpoint ahead of
// time.
import { createClient } from "npm:@supabase/supabase-js@2";

const FOODICS_API_BASE =
  Deno.env.get("FOODICS_API_BASE") ?? "https://api.foodics.com/v5";
const CLOSED_STATUS = 4;
const DEFAULT_LOOKBACK_DAYS = 14;
const CHUNK_SIZE = 500;
const MAX_PAGES = 100; // safety cap (~20k orders) against a runaway loop

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function parseDate(value: string | undefined | null): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function normalizeName(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, " ");
}

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size)
    chunks.push(items.slice(i, i + size));
  return chunks;
}

type FoodicsProductLine = {
  product?: { id: string; name: string } | null;
  quantity: number;
  returned_quantity?: number | null;
  unit_price: number;
};

type FoodicsOrder = {
  id: string;
  status: number;
  business_date: string;
  closed_at: string | null;
  updated_at: string;
  total_price: number;
  branch?: { id: string; name: string } | null;
  products?: FoodicsProductLine[];
};

async function fetchClosedOrders(
  businessDateAfter: string,
  businessDateBefore: string | null,
  token: string
): Promise<FoodicsOrder[]> {
  const orders: FoodicsOrder[] = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const url = new URL(`${FOODICS_API_BASE}/orders`);
    url.searchParams.set("business_date_after", businessDateAfter);
    if (businessDateBefore) {
      url.searchParams.set("business_date_before", businessDateBefore);
    }
    url.searchParams.set("status", String(CLOSED_STATUS));
    url.searchParams.set("include", "branch,products.product");
    url.searchParams.set("page", String(page));

    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
    });
    if (!res.ok) {
      throw new Error(`Foodics API error ${res.status}: ${await res.text()}`);
    }
    const body = await res.json();
    const pageData: FoodicsOrder[] = body.data ?? [];
    orders.push(...pageData);
    if (pageData.length === 0) break;
  }
  return orders;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const foodicsToken = Deno.env.get("FOODICS_API_TOKEN");

    if (!foodicsToken) {
      return json({ error: "FOODICS_API_TOKEN secret is not configured" }, 500);
    }

    // Authorize the caller using their own JWT (never trust the client to
    // self-report role) before doing any privileged work.
    const authHeader = req.headers.get("Authorization") ?? "";
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
    } = await callerClient.auth.getUser();
    if (!user) return json({ error: "Not authenticated" }, 401);

    const { data: profile } = await callerClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();
    if (!profile || !["admin", "accountant"].includes(profile.role)) {
      return json({ error: "Not authorized to sync Foodics data" }, 403);
    }

    const db = createClient(supabaseUrl, serviceRoleKey);

    // Chunked backfill mode: an explicit {from, to} body bypasses the
    // "since last sync" logic entirely, so callers can walk historical
    // date ranges in safe, resumable windows.
    let requestBody: { from?: string; to?: string } = {};
    try {
      const text = await req.text();
      if (text) requestBody = JSON.parse(text);
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    let businessDateAfter: string;
    let businessDateBefore: string | null = null;

    if (requestBody.from) {
      if (
        !DATE_RE.test(requestBody.from) ||
        (requestBody.to && !DATE_RE.test(requestBody.to))
      ) {
        return json({ error: "from/to must be YYYY-MM-DD" }, 400);
      }
      businessDateAfter = requestBody.from;
      businessDateBefore = requestBody.to ?? null;
    } else {
      const { data: lastOrder } = await db
        .from("sales_orders")
        .select("order_date")
        .eq("source", "foodics")
        .order("order_date", { ascending: false })
        .limit(1)
        .maybeSingle();

      businessDateAfter = lastOrder?.order_date
        ? new Date(new Date(lastOrder.order_date).getTime() - 24 * 3600 * 1000)
            .toISOString()
            .slice(0, 10)
        : new Date(Date.now() - DEFAULT_LOOKBACK_DAYS * 24 * 3600 * 1000)
            .toISOString()
            .slice(0, 10);
    }

    const rawOrders = await fetchClosedOrders(
      businessDateAfter,
      businessDateBefore,
      foodicsToken
    );

    const { data: aliases } = await db
      .from("location_aliases")
      .select("source_name, location_id, brand")
      .eq("source", "foodics");
    const aliasMap = new Map((aliases ?? []).map((a) => [a.source_name, a]));

    const { data: products } = await db
      .from("products")
      .select("id, name_en, name_ar");
    const { data: productAliases } = await db
      .from("product_aliases")
      .select("raw_name, product_id");
    const productByName = new Map<string, string>();
    for (const p of products ?? []) {
      productByName.set(normalizeName(p.name_en), p.id);
      productByName.set(normalizeName(p.name_ar), p.id);
    }
    const productByAlias = new Map<string, string>(
      (productAliases ?? []).map((a) => [
        normalizeName(a.raw_name),
        a.product_id,
      ])
    );
    function resolveProductId(itemName: string): string | null {
      const key = normalizeName(itemName);
      return productByName.get(key) ?? productByAlias.get(key) ?? null;
    }

    type Resolved = {
      externalRef: string;
      location_id: string;
      brand: string | null;
      orderDate: string;
      gross: number;
      lines: { itemName: string; qty: number; unitPrice: number }[];
    };
    const resolved: Resolved[] = [];
    const unresolvedBranch: { order: FoodicsOrder; reason: string }[] = [];
    const invalid: { order: FoodicsOrder; reason: string }[] = [];

    for (const order of rawOrders) {
      const orderDate = parseDate(order.closed_at ?? order.updated_at);
      if (
        !order.id ||
        !order.branch?.name ||
        orderDate === null ||
        order.total_price == null
      ) {
        invalid.push({
          order,
          reason: "Missing id / branch / closed_at / total_price",
        });
        continue;
      }
      const alias = aliasMap.get(order.branch.name);
      if (!alias) {
        unresolvedBranch.push({
          order,
          reason: `No location_alias found for branch name "${order.branch.name}" (source: foodics)`,
        });
        continue;
      }
      const lines = (order.products ?? [])
        .map((p) => ({
          itemName: (p.product?.name ?? "").trim(),
          qty: p.quantity - (p.returned_quantity ?? 0),
          unitPrice: p.unit_price,
        }))
        .filter((l) => l.itemName && l.qty > 0);

      resolved.push({
        externalRef: order.id,
        location_id: alias.location_id,
        brand: alias.brand,
        orderDate,
        gross: round2(order.total_price),
        lines,
      });
    }

    const { data: importFile, error: importFileError } = await db
      .from("import_files")
      .insert({
        source: "foodics",
        filename: `foodics-sync-${new Date().toISOString()}`,
        row_count: rawOrders.length,
        uploaded_by: user.id,
      })
      .select("id")
      .single();
    if (importFileError || !importFile)
      throw importFileError ?? new Error("Failed to create import_files row");
    const importFileId = importFile.id;

    const rejects = [...unresolvedBranch, ...invalid].map(
      ({ order, reason }) => ({
        import_file_id: importFileId,
        raw_row: order,
        reason,
      })
    );
    for (const batch of chunk(rejects, CHUNK_SIZE)) {
      if (batch.length === 0) continue;
      const { error } = await db.from("import_rejects").insert(batch);
      if (error) throw error;
    }

    let insertedCount = 0;
    let lineMatchedCount = 0;
    let lineUnmatchedCount = 0;

    for (const batch of chunk(resolved, CHUNK_SIZE)) {
      const { data: upserted, error: upsertError } = await db
        .from("sales_orders")
        .upsert(
          batch.map((o) => ({
            source: "foodics" as const,
            external_ref: o.externalRef,
            location_id: o.location_id,
            brand: o.brand,
            order_date: o.orderDate,
            gross: o.gross,
            commission: 0,
            net: o.gross,
            import_file_id: importFileId,
          })),
          { onConflict: "source,external_ref", ignoreDuplicates: true }
        )
        .select("id");
      if (upsertError) throw upsertError;
      insertedCount += upserted?.length ?? 0;

      const { data: orderIdRows, error: lookupError } = await db
        .from("sales_orders")
        .select("id, external_ref")
        .eq("source", "foodics")
        .in(
          "external_ref",
          batch.map((o) => o.externalRef)
        );
      if (lookupError) throw lookupError;
      const orderIdByRef = new Map(
        (orderIdRows ?? []).map((r) => [r.external_ref, r.id])
      );

      for (const o of batch) {
        const orderId = orderIdByRef.get(o.externalRef);
        if (!orderId) continue;

        const { error: deleteError } = await db
          .from("sales_lines")
          .delete()
          .eq("order_id", orderId);
        if (deleteError) throw deleteError;

        const lineRows = o.lines.map((line) => {
          const productId = resolveProductId(line.itemName);
          if (productId) lineMatchedCount += 1;
          else lineUnmatchedCount += 1;
          return {
            order_id: orderId,
            product_id: productId,
            qty: line.qty,
            raw_item_name: line.itemName,
            unit_price: line.unitPrice,
          };
        });
        if (lineRows.length > 0) {
          const { error: insertLinesError } = await db
            .from("sales_lines")
            .insert(lineRows);
          if (insertLinesError) throw insertLinesError;
        }
      }
    }

    return json({
      windowFrom: businessDateAfter,
      windowTo: businessDateBefore,
      totalFetched: rawOrders.length,
      resolvedCount: resolved.length,
      unresolvedCount: unresolvedBranch.length,
      invalidCount: invalid.length,
      insertedCount,
      lineMatchedCount,
      lineUnmatchedCount,
    });
  } catch (err) {
    console.error("foodics-sync failed:", err);
    return json(
      { error: err instanceof Error ? err.message : "Unknown error" },
      500
    );
  }
});

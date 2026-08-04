import type { NormalizedOrderLine, NormalizeResult, SourceAdapter } from "./types";
import { parseDate, parseNumber, round2 } from "./utils";

const VALID_STATUSES = new Set(["Delivered", "Picked up"]);

const REQUIRED_HEADERS = [
  "Order ID",
  "Restaurant name",
  "Order received at",
  "Subtotal",
];

// Matches "<qty> <name>" with an optional trailing "[<bracket>]", e.g.
// "2 Sweet Heat Burger [1 Sandwich]" or "1 Chili Sauce". Verified against
// a real 2,500-row Talabat export (FLU-13) with zero unparsed segments.
const ITEM_RE = /^(\d+)\s+(.+?)(?:\s*\[(.*)\]\s*)?$/s;

/** Splits a Talabat "Order Items" cell on top-level commas only --
 * commas inside a "[...]" bracket (combo/size sub-choices) don't split. */
function splitTopLevel(cell: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let current = "";
  for (const ch of cell) {
    if (ch === "[") {
      depth += 1;
      current += ch;
    } else if (ch === "]") {
      depth -= 1;
      current += ch;
    } else if (ch === "," && depth === 0) {
      parts.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  if (current.trim()) parts.push(current);
  return parts.map((p) => p.trim()).filter(Boolean);
}

/** Parses the packed "Order Items" cell into a clean per-item breakdown.
 *
 * A bracket that's a single simple choice (no comma inside, e.g.
 * "[1 Meal]", "[1 Sandwich]", "[1 Small]") names a distinct priced SKU and
 * is folded into the item name ("Fluffy Burger" + "Meal" -> "Fluffy Burger
 * Meal"). A bracket listing several comma-separated sub-items (e.g. "Meal
 * for 3 people [1 Bee Burger, 1 Chilli Burger, ...]") describes a combo's
 * customer-chosen contents, not a separate SKU or line item -- it's
 * dropped, matching on the bundle's own top-level name instead.
 */
export function parseOrderItems(cell: string | undefined): NormalizedOrderLine[] {
  if (!cell || !cell.trim()) return [];

  return splitTopLevel(cell).map((segment): NormalizedOrderLine => {
    const match = segment.match(ITEM_RE);
    if (!match) return { itemName: segment, qty: 1 };

    const qty = Number(match[1]);
    const topName = match[2].trim();
    const bracket = match[3]?.trim();

    if (!bracket || bracket.includes(",")) {
      return { itemName: topName, qty };
    }

    const variant = bracket.replace(/^\d+\s+/, "").trim();
    return { itemName: variant ? `${topName} ${variant}` : topName, qty };
  });
}

function normalize(rows: Record<string, string>[]): NormalizeResult {
  const orders: NormalizeResult["orders"] = [];
  const invalidRows: NormalizeResult["invalidRows"] = [];
  let excludedCount = 0;

  rows.forEach((row, i) => {
    const rowNumber = i + 2; // +1 for header row, +1 for 1-indexing

    const status = row["Order status"]?.trim();
    if (status && !VALID_STATUSES.has(status)) {
      excludedCount += 1;
      return;
    }

    const externalRef = row["Order ID"]?.trim();
    const branchName = row["Restaurant name"]?.trim();
    const orderDate = parseDate(row["Order received at"]);
    const gross = parseNumber(row["Subtotal"]);
    const commissionBase = parseNumber(row["Commission"]) ?? 0;
    const marketingFees = parseNumber(row["Marketing Fees Total"]) ?? 0;

    if (!externalRef || !branchName || !orderDate || gross === null) {
      invalidRows.push({
        rowNumber,
        raw: row,
        reason:
          "Missing or unparseable Order ID / Restaurant name / Order received at / Subtotal",
      });
      return;
    }

    const commission = round2(commissionBase + marketingFees);
    orders.push({
      externalRef,
      branchName,
      orderDate,
      gross: round2(gross),
      commission,
      lines: parseOrderItems(row["Order Items"]),
      net: round2(gross - commission),
    });
  });

  return { orders, excludedCount, invalidRows };
}

export const talabatAdapter: SourceAdapter = {
  source: "talabat",
  label: "Talabat",
  detect: (headers) => REQUIRED_HEADERS.every((h) => headers.includes(h)),
  normalize,
};

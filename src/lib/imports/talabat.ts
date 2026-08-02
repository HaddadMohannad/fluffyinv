import type { NormalizeResult, SourceAdapter } from "./types";
import { parseDate, parseNumber, round2 } from "./utils";

const VALID_STATUSES = new Set(["Delivered", "Picked up"]);

const REQUIRED_HEADERS = [
  "Order ID",
  "Restaurant name",
  "Order received at",
  "Subtotal",
];

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

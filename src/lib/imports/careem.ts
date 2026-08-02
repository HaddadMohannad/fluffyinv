import type { NormalizeResult, SourceAdapter } from "./types";
import { parseDate, parseNumber, round2 } from "./utils";

const VALID_STATUS = "Delivered";
const VALID_ENTRY_TYPE = "FOOD_ORDER";

const REQUIRED_HEADERS = [
  "REFERENCE_ID",
  "MERCHANT_NAME",
  "MERCHANT_AREA",
  "TRANSACTION_DATE",
  "FOOD_GROSS_BASKET_AMOUNT",
];

function abs(value: string | undefined): number {
  const n = parseNumber(value);
  return n === null ? 0 : Math.abs(n);
}

function normalize(rows: Record<string, string>[]): NormalizeResult {
  const orders: NormalizeResult["orders"] = [];
  const invalidRows: NormalizeResult["invalidRows"] = [];
  let excludedCount = 0;

  rows.forEach((row, i) => {
    const rowNumber = i + 2;

    const status = row["STATUS"]?.trim();
    const entryType = row["ENTRY_TYPE"]?.trim();
    if (
      (status && status !== VALID_STATUS) ||
      (entryType && entryType !== VALID_ENTRY_TYPE)
    ) {
      excludedCount += 1;
      return;
    }

    const externalRef = row["REFERENCE_ID"]?.trim();
    const merchantName = row["MERCHANT_NAME"]?.trim();
    const merchantArea = row["MERCHANT_AREA"]?.trim();
    const orderDate = parseDate(row["TRANSACTION_DATE"]);
    const gross = parseNumber(row["FOOD_GROSS_BASKET_AMOUNT"]);
    const netFromFile = parseNumber(row["TOTAL_PAYOUT_AMOUNT"]);

    if (
      !externalRef ||
      !merchantName ||
      !merchantArea ||
      !orderDate ||
      gross === null
    ) {
      invalidRows.push({
        rowNumber,
        raw: row,
        reason:
          "Missing or unparseable REFERENCE_ID / MERCHANT_NAME / MERCHANT_AREA / TRANSACTION_DATE / FOOD_GROSS_BASKET_AMOUNT",
      });
      return;
    }

    const commission = round2(
      abs(row["BILLING_PLATFORM_FEE"]) +
        abs(row["BILLING_PLATFORM_FEE_TAX"]) +
        abs(row["BILLING_PAYMENT_GATEWAY_FEE"]) +
        abs(row["BILLING_PAYMENT_GATEWAY_FEE_TAX"])
    );

    orders.push({
      externalRef,
      branchName: `${merchantName} - ${merchantArea}`,
      orderDate,
      gross: round2(gross),
      commission,
      net:
        netFromFile !== null ? round2(netFromFile) : round2(gross - commission),
    });
  });

  return { orders, excludedCount, invalidRows };
}

export const careemAdapter: SourceAdapter = {
  source: "careem",
  label: "Careem",
  detect: (headers) => REQUIRED_HEADERS.every((h) => headers.includes(h)),
  normalize,
};

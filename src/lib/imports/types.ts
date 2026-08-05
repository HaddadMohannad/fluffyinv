export type ImportSource = "talabat" | "careem" | "foodics";

export type ParsedCsv = {
  headers: string[];
  rows: Record<string, string>[];
};

export type NormalizedOrderLine = {
  /** Clean, matchable item name (e.g. "Fluffy Burger Meal") -- no leading
   * quantity (kept separately in `qty`) and no combo-bundle sub-item detail. */
  itemName: string;
  qty: number;
};

export type NormalizedOrder = {
  externalRef: string;
  branchName: string;
  orderDate: string; // ISO 8601
  gross: number;
  commission: number;
  net: number;
  /** Per-item breakdown, when the source format supports it (currently Talabat only). */
  lines?: NormalizedOrderLine[];
};

export type NormalizeResult = {
  orders: NormalizedOrder[];
  /** Rows excluded on purpose (e.g. non-final order status) — not data errors. */
  excludedCount: number;
  /** Rows that couldn't be normalized at all (bad/missing required fields). */
  invalidRows: {
    rowNumber: number;
    raw: Record<string, string>;
    reason: string;
  }[];
};

export type SourceAdapter = {
  source: ImportSource;
  label: string;
  /** Returns true if this CSV's headers look like this source's export format. */
  detect: (headers: string[]) => boolean;
  normalize: (rows: Record<string, string>[]) => NormalizeResult;
};

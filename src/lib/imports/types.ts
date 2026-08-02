export type ImportSource = "talabat" | "careem" | "foodics";

export type ParsedCsv = {
  headers: string[];
  rows: Record<string, string>[];
};

export type NormalizedOrder = {
  externalRef: string;
  branchName: string;
  orderDate: string; // ISO 8601
  gross: number;
  commission: number;
  net: number;
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

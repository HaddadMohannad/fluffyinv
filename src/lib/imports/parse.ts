import Papa from "papaparse";
import type { ParsedCsv } from "./types";

export function fileToRows(file: File): Promise<ParsedCsv> {
  return new Promise((resolve, reject) => {
    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        resolve({
          headers: results.meta.fields ?? [],
          rows: results.data,
        });
      },
      error: (error: Error) => reject(error),
    });
  });
}

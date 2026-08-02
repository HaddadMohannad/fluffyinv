import type { SourceAdapter } from "./types";
import { talabatAdapter } from "./talabat";
import { careemAdapter } from "./careem";

export const adapters: SourceAdapter[] = [talabatAdapter, careemAdapter];

export function detectAdapter(headers: string[]): SourceAdapter | null {
  return adapters.find((a) => a.detect(headers)) ?? null;
}

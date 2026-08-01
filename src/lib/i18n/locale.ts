import { cookies } from "next/headers";
import { locales, type Locale } from "./dictionary";

export const LOCALE_COOKIE = "fluffy_locale";

export async function getLocale(): Promise<Locale> {
  const cookieStore = await cookies();
  const value = cookieStore.get(LOCALE_COOKIE)?.value;
  return (locales as readonly string[]).includes(value ?? "")
    ? (value as Locale)
    : "en";
}

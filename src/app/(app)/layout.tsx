import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/session";
import { getLocale } from "@/lib/i18n/locale";
import { AppShell } from "@/components/AppShell";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [currentUser, locale] = await Promise.all([
    getCurrentUser(),
    getLocale(),
  ]);

  if (!currentUser) {
    redirect("/login");
  }

  return <AppShell locale={locale}>{children}</AppShell>;
}

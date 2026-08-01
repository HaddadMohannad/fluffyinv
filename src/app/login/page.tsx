import { getLocale } from "@/lib/i18n/locale";
import { LoginForm } from "./LoginForm";

export default async function LoginPage() {
  const locale = await getLocale();
  return <LoginForm locale={locale} />;
}

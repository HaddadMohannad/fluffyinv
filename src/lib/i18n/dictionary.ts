export const locales = ["en", "ar"] as const;
export type Locale = (typeof locales)[number];

export const dictionary = {
  en: {
    appName: "Fluffy Inventory",
    signIn: "Sign in",
    signingIn: "Signing in…",
    email: "Email",
    password: "Password",
    signOut: "Sign out",
    home: "Home",
    noProfile:
      "Signed in, but no profile record exists for this account yet — ask an admin to create one.",
    switchToLabel: "العربية",
  },
  ar: {
    appName: "فلافي - المخزون",
    signIn: "تسجيل الدخول",
    signingIn: "جارٍ تسجيل الدخول…",
    email: "البريد الإلكتروني",
    password: "كلمة المرور",
    signOut: "تسجيل الخروج",
    home: "الرئيسية",
    noProfile:
      "تم تسجيل الدخول، لكن لا يوجد سجل ملف شخصي لهذا الحساب بعد — يرجى التواصل مع المسؤول لإنشائه.",
    switchToLabel: "English",
  },
} as const satisfies Record<Locale, Record<string, string>>;

export function dir(locale: Locale): "rtl" | "ltr" {
  return locale === "ar" ? "rtl" : "ltr";
}

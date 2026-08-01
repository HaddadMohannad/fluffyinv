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
    rememberMe: "Remember me",
    forgotPassword: "Forgot password?",
    backToSignIn: "Back to sign in",
    resetPasswordTitle: "Reset password",
    resetPasswordInstructions:
      "Enter your email and we'll send you a link to reset your password.",
    sendResetLink: "Send reset link",
    sendingResetLink: "Sending…",
    resetLinkSent:
      "If an account exists for that email, a reset link has been sent. Check your inbox.",
    newPasswordTitle: "Set a new password",
    newPassword: "New password",
    confirmPassword: "Confirm password",
    updatePassword: "Update password",
    updatingPassword: "Updating…",
    passwordMismatch: "Passwords don't match.",
    passwordUpdated: "Password updated. You can now sign in.",
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
    rememberMe: "تذكرني",
    forgotPassword: "نسيت كلمة المرور؟",
    backToSignIn: "العودة لتسجيل الدخول",
    resetPasswordTitle: "إعادة تعيين كلمة المرور",
    resetPasswordInstructions:
      "أدخل بريدك الإلكتروني وسنرسل لك رابطًا لإعادة تعيين كلمة المرور.",
    sendResetLink: "إرسال رابط إعادة التعيين",
    sendingResetLink: "جارٍ الإرسال…",
    resetLinkSent:
      "إذا كان هناك حساب مرتبط بهذا البريد الإلكتروني، فقد تم إرسال رابط إعادة التعيين. تحقق من بريدك الوارد.",
    newPasswordTitle: "تعيين كلمة مرور جديدة",
    newPassword: "كلمة المرور الجديدة",
    confirmPassword: "تأكيد كلمة المرور",
    updatePassword: "تحديث كلمة المرور",
    updatingPassword: "جارٍ التحديث…",
    passwordMismatch: "كلمتا المرور غير متطابقتين.",
    passwordUpdated: "تم تحديث كلمة المرور. يمكنك الآن تسجيل الدخول.",
  },
} as const satisfies Record<Locale, Record<string, string>>;

export type Strings = { [K in keyof (typeof dictionary)["en"]]: string };

export function dir(locale: Locale): "rtl" | "ltr" {
  return locale === "ar" ? "rtl" : "ltr";
}

import type { ReactNode } from "react";
import { signOut } from "@/app/actions/auth";
import { LanguageToggle } from "@/components/LanguageToggle";
import { dictionary } from "@/lib/i18n/dictionary";
import type { Locale } from "@/lib/i18n/dictionary";

type NavItem = { href: string; labelKey: keyof (typeof dictionary)["en"] };

const NAV_ITEMS: NavItem[] = [{ href: "/", labelKey: "home" }];

export function AppShell({
  children,
  locale,
}: {
  children: ReactNode;
  locale: Locale;
}) {
  const t = dictionary[locale];

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <header className="flex h-14 shrink-0 items-center justify-between border-b border-zinc-200 px-4 dark:border-zinc-800">
        <span className="text-fluffy-dark text-lg font-semibold dark:text-zinc-50">
          {t.appName}
        </span>
        <div className="flex items-center gap-2">
          <LanguageToggle locale={locale} label={t.switchToLabel} />
          <form action={signOut}>
            <button
              type="submit"
              className="h-11 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
            >
              {t.signOut}
            </button>
          </form>
        </div>
      </header>

      <div className="flex flex-1">
        <nav className="hidden w-48 shrink-0 border-e border-zinc-200 p-4 md:block dark:border-zinc-800">
          <ul className="flex flex-col gap-1">
            {NAV_ITEMS.map((item) => (
              <li key={item.href}>
                <a
                  href={item.href}
                  className="flex h-11 items-center rounded-md px-3 text-sm font-medium hover:bg-zinc-100 dark:hover:bg-zinc-900"
                >
                  {t[item.labelKey]}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <main className="flex flex-1 flex-col pb-16 md:pb-0">{children}</main>
      </div>

      <nav className="fixed inset-x-0 bottom-0 flex h-16 border-t border-zinc-200 bg-white md:hidden dark:border-zinc-800 dark:bg-black">
        {NAV_ITEMS.map((item) => (
          <a
            key={item.href}
            href={item.href}
            className="flex flex-1 flex-col items-center justify-center gap-1 text-sm font-medium"
          >
            {t[item.labelKey]}
          </a>
        ))}
      </nav>
    </div>
  );
}

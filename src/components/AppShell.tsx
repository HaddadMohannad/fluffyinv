import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { LanguageToggle } from "@/components/LanguageToggle";
import { dictionary } from "@/lib/i18n/dictionary";

type NavItem = {
  href: string;
  labelKey: keyof (typeof dictionary)["en"];
  roles?: Array<"admin" | "branch_manager" | "warehouse_staff" | "accountant">;
};

const NAV_ITEMS: NavItem[] = [
  { href: "/", labelKey: "home" },
  { href: "/sales", labelKey: "sales" },
  { href: "/import", labelKey: "import", roles: ["admin", "accountant"] },
  {
    href: "/opening-stock",
    labelKey: "openingStock",
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  {
    href: "/purchase",
    labelKey: "purchase",
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  {
    href: "/transfer",
    labelKey: "transfer",
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  {
    href: "/stocktake",
    labelKey: "stocktake",
    roles: ["admin", "branch_manager"],
  },
  {
    href: "/hospitality",
    labelKey: "hospitality",
    roles: ["admin", "branch_manager"],
  },
  {
    href: "/waste",
    labelKey: "waste",
    roles: ["admin", "branch_manager"],
  },
  {
    href: "/lookup-lists",
    labelKey: "lookupLists",
    roles: ["admin"],
  },
];

export function AppShell({ children }: { children: ReactNode }) {
  const { t } = useLocale();
  const { signOut, profile } = useAuth();

  const visibleItems = NAV_ITEMS.filter(
    (item) =>
      !item.roles || (profile?.role && item.roles.includes(profile.role))
  );

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <header className="flex h-14 shrink-0 items-center justify-between border-b border-zinc-200 px-4 dark:border-zinc-800">
        <span className="text-fluffy-dark text-lg font-semibold dark:text-zinc-50">
          {t.appName}
        </span>
        <div className="flex items-center gap-2">
          <LanguageToggle />
          <button
            type="button"
            onClick={() => signOut()}
            className="h-11 rounded-md border border-zinc-300 px-3 text-sm font-medium dark:border-zinc-700"
          >
            {t.signOut}
          </button>
        </div>
      </header>

      <div className="flex flex-1">
        <nav className="hidden w-48 shrink-0 border-e border-zinc-200 p-4 md:block dark:border-zinc-800">
          <ul className="flex flex-col gap-1">
            {visibleItems.map((item) => (
              <li key={item.href}>
                <Link
                  to={item.href}
                  className="flex h-11 items-center rounded-md px-3 text-sm font-medium hover:bg-zinc-100 dark:hover:bg-zinc-900"
                >
                  {t[item.labelKey]}
                </Link>
              </li>
            ))}
          </ul>
        </nav>

        <main className="flex flex-1 flex-col pb-16 md:pb-0">{children}</main>
      </div>

      <nav className="fixed inset-x-0 bottom-0 flex h-16 gap-1 overflow-x-auto border-t border-zinc-200 bg-white md:hidden dark:border-zinc-800 dark:bg-black">
        {visibleItems.map((item) => (
          <Link
            key={item.href}
            to={item.href}
            className="flex min-w-20 shrink-0 flex-col items-center justify-center gap-1 whitespace-nowrap px-2 text-xs font-medium"
          >
            {t[item.labelKey]}
          </Link>
        ))}
      </nav>
    </div>
  );
}

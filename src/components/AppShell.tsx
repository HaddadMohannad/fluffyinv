import { useState, type ReactNode } from "react";
import { Link, useLocation } from "react-router";
import {
  ChefHat,
  ChevronDown,
  MapPin,
  LogOut,
  MoreHorizontal,
  X,
} from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { LanguageToggle } from "@/components/LanguageToggle";
import { NAV_ITEMS, type NavItem } from "@/lib/navigation";

function initialsOf(name: string | null | undefined) {
  if (!name) return "?";
  return (
    name
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((w) => w[0]?.toUpperCase())
      .join("") || "?"
  );
}

export function AppShell({
  children,
  title,
}: {
  children: ReactNode;
  title?: string;
}) {
  const { t, locale } = useLocale();
  const { signOut, profile, location } = useAuth();
  const { locations, locationId, isLocationLocked, setSelectedLocationId } =
    useActiveLocation();
  const routerLocation = useLocation();

  const visibleItems = NAV_ITEMS.filter((item) => {
    // Home always shows — it's where the pending-approval message lives
    // for a session with no profile yet. Everything else needs a profile.
    if (item.href === "/") return true;
    if (!profile) return false;
    return !item.roles || item.roles.includes(profile.role);
  });

  const activeLocationName = isLocationLocked
    ? location
      ? locale === "ar"
        ? location.name_ar
        : location.name_en
      : ""
    : (locations.find((l) => l.id === locationId) &&
        (locale === "ar"
          ? locations.find((l) => l.id === locationId)!.name_ar
          : locations.find((l) => l.id === locationId)!.name_en)) ||
      "";

  return (
    <div className="flex min-h-full flex-1 flex-col bg-zinc-50 dark:bg-zinc-950">
      <div className="flex flex-1">
        <nav className="hidden w-56 shrink-0 flex-col border-e border-zinc-200 bg-white md:flex dark:border-zinc-800 dark:bg-zinc-900">
          <div className="flex h-14 items-center gap-2 border-b border-zinc-200 px-4 dark:border-zinc-800">
            <span className="bg-fluffy-orange flex h-8 w-8 items-center justify-center rounded-lg text-white">
              <ChefHat className="h-5 w-5" />
            </span>
            <span className="text-fluffy-dark truncate text-lg font-semibold dark:text-zinc-50">
              {t.appName}
            </span>
          </div>
          <ul className="flex flex-1 flex-col gap-1 overflow-y-auto p-3">
            {visibleItems.map((item) => {
              const isActive = routerLocation.pathname === item.href;
              const Icon = item.icon;
              return (
                <li key={item.href}>
                  <Link
                    to={item.href}
                    className={`flex h-11 items-center gap-3 rounded-md px-3 text-sm font-medium ${
                      isActive
                        ? "bg-fluffy-orange text-white"
                        : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800"
                    }`}
                  >
                    <Icon className="h-4 w-4 shrink-0" />
                    <span className="truncate">{t[item.labelKey]}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="flex flex-1 flex-col">
          <header className="flex h-14 shrink-0 items-center justify-between gap-3 border-b border-zinc-200 bg-white px-4 dark:border-zinc-800 dark:bg-zinc-900">
            <h1 className="text-fluffy-dark min-w-0 truncate text-base font-semibold dark:text-zinc-50">
              <span className="hidden sm:inline">
                {activeLocationName ? `${activeLocationName} — ` : ""}
              </span>
              {title ?? t.appName}
            </h1>
            <div className="flex shrink-0 items-center gap-2">
              {profile &&
                (isLocationLocked ? (
                  location && (
                    <span className="flex max-w-[7rem] items-center gap-1 rounded-full border border-zinc-300 px-3 py-1.5 text-sm font-medium sm:max-w-none dark:border-zinc-700">
                      <MapPin className="h-3.5 w-3.5 shrink-0" />
                      <span className="truncate">{activeLocationName}</span>
                    </span>
                  )
                ) : (
                  <div className="relative">
                    <MapPin className="text-fluffy-orange pointer-events-none absolute start-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2" />
                    <select
                      value={locationId}
                      onChange={(e) => setSelectedLocationId(e.target.value)}
                      className="h-9 max-w-[7rem] appearance-none truncate rounded-full border border-zinc-300 bg-transparent ps-8 pe-7 text-sm font-medium sm:max-w-none dark:border-zinc-700"
                    >
                      {locations.map((l) => (
                        <option key={l.id} value={l.id}>
                          {locale === "ar" ? l.name_ar : l.name_en}
                        </option>
                      ))}
                    </select>
                    <ChevronDown className="pointer-events-none absolute end-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2" />
                  </div>
                ))}
              <LanguageToggle />
              {profile && (
                <span
                  title={profile.full_name}
                  className="bg-fluffy-orange flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-white"
                >
                  {initialsOf(profile.full_name)}
                </span>
              )}
              <button
                type="button"
                onClick={() => signOut()}
                aria-label={t.signOut}
                title={t.signOut}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-zinc-300 dark:border-zinc-700"
              >
                <LogOut className="h-4 w-4" />
              </button>
            </div>
          </header>

          <main className="flex flex-1 flex-col overflow-y-auto pb-16 md:pb-0">
            {children}
          </main>
        </div>
      </div>

      <MobileNav items={visibleItems} activePath={routerLocation.pathname} />
    </div>
  );
}

function MobileNav({
  items,
  activePath,
}: {
  items: NavItem[];
  activePath: string;
}) {
  const { t } = useLocale();
  const [open, setOpen] = useState(false);

  const primary = items.slice(0, 4);
  const rest = items.slice(4);

  return (
    <>
      <nav className="fixed inset-x-0 bottom-0 flex h-16 border-t border-zinc-200 bg-white md:hidden dark:border-zinc-800 dark:bg-black">
        {primary.map((item) => {
          const Icon = item.icon;
          const isActive = activePath === item.href;
          return (
            <Link
              key={item.href}
              to={item.href}
              className={`flex flex-1 flex-col items-center justify-center gap-0.5 text-[11px] font-medium ${
                isActive
                  ? "text-fluffy-orange"
                  : "text-zinc-600 dark:text-zinc-400"
              }`}
            >
              <Icon className="h-5 w-5" />
              <span className="truncate px-1">{t[item.labelKey]}</span>
            </Link>
          );
        })}
        {rest.length > 0 && (
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="flex flex-1 flex-col items-center justify-center gap-0.5 text-[11px] font-medium text-zinc-600 dark:text-zinc-400"
          >
            <MoreHorizontal className="h-5 w-5" />
            <span>{t.moreNavLabel}</span>
          </button>
        )}
      </nav>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-end bg-black/50 md:hidden"
          onClick={() => setOpen(false)}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="max-h-[70vh] w-full overflow-y-auto rounded-t-2xl bg-white p-4 dark:bg-zinc-900"
          >
            <div className="mb-3 flex items-center justify-between">
              <span className="text-sm font-semibold">{t.moreNavLabel}</span>
              <button
                type="button"
                onClick={() => setOpen(false)}
                aria-label={t.closeModal}
              >
                <X className="h-5 w-5" />
              </button>
            </div>
            <ul className="grid grid-cols-3 gap-3">
              {rest.map((item) => {
                const Icon = item.icon;
                return (
                  <li key={item.href}>
                    <Link
                      to={item.href}
                      onClick={() => setOpen(false)}
                      className="flex flex-col items-center gap-1 rounded-md p-2 text-xs font-medium text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800"
                    >
                      <Icon className="h-5 w-5" />
                      <span className="text-center">{t[item.labelKey]}</span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        </div>
      )}
    </>
  );
}

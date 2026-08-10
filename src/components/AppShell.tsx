import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Link, useLocation } from "react-router";
import { ChefHat, ChevronDown, MapPin, LogOut, Menu, X } from "lucide-react";
import { useAuth } from "@/lib/auth/AuthContext";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { useActiveLocation } from "@/lib/location/LocationContext";
import { LanguageToggle } from "@/components/LanguageToggle";
import {
  NAV_GROUPS,
  NAV_ITEMS,
  groupNavItems,
  roleDefaultHrefs,
  type NavItem,
} from "@/lib/navigation";
import { supabase } from "@/lib/supabase/client";

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

function NavList({
  items,
  activePath,
  onNavigate,
}: {
  items: NavItem[];
  activePath: string;
  onNavigate?: () => void;
}) {
  const { t } = useLocale();
  const nodes = useMemo(() => groupNavItems(items), [items]);
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set());

  // Keep the group containing the current page expanded, so a reload or
  // a direct link doesn't leave you inside a group with no visible cue
  // of where you are.
  useEffect(() => {
    const activeGroup = NAV_GROUPS.find((g) => g.hrefs.includes(activePath));
    if (!activeGroup) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- recovering the expanded state a route change implies (the group containing the new active page should read as open)
    setExpanded((prev) =>
      prev.has(activeGroup.key) ? prev : new Set(prev).add(activeGroup.key)
    );
  }, [activePath]);

  function toggleGroup(key: string) {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  return (
    <ul className="flex flex-1 flex-col gap-1 overflow-y-auto p-3">
      {nodes.map((node) => {
        if (node.kind === "item") {
          const isActive = activePath === node.item.href;
          const Icon = node.item.icon;
          return (
            <li key={node.item.href}>
              <Link
                to={node.item.href}
                onClick={onNavigate}
                className={`flex h-11 items-center gap-3 rounded-md px-3 text-sm font-medium ${
                  isActive
                    ? "bg-fluffy-orange text-white"
                    : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800"
                }`}
              >
                <Icon className="h-4 w-4 shrink-0" />
                <span className="truncate">{t[node.item.labelKey]}</span>
              </Link>
            </li>
          );
        }

        const isOpen = expanded.has(node.group.key);
        const hasActiveChild = node.items.some((i) => i.href === activePath);
        const GroupIcon = node.group.icon;
        return (
          <li key={node.group.key}>
            <button
              type="button"
              onClick={() => toggleGroup(node.group.key)}
              aria-expanded={isOpen}
              className={`flex h-11 w-full items-center gap-3 rounded-md px-3 text-sm font-medium ${
                hasActiveChild && !isOpen
                  ? "text-fluffy-orange bg-orange-50 dark:bg-orange-950"
                  : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800"
              }`}
            >
              <GroupIcon className="h-4 w-4 shrink-0" />
              <span className="flex-1 truncate text-start">
                {t[node.group.labelKey]}
              </span>
              <ChevronDown
                className={`h-4 w-4 shrink-0 transition-transform ${isOpen ? "rotate-180" : ""}`}
              />
            </button>
            {isOpen && (
              <ul className="mt-1 flex flex-col gap-1 ps-4">
                {node.items.map((item) => {
                  const isActive = activePath === item.href;
                  const Icon = item.icon;
                  return (
                    <li key={item.href}>
                      <Link
                        to={item.href}
                        onClick={onNavigate}
                        className={`flex h-10 items-center gap-3 rounded-md px-3 text-sm font-medium ${
                          isActive
                            ? "bg-fluffy-orange text-white"
                            : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800"
                        }`}
                      >
                        <Icon className="h-3.5 w-3.5 shrink-0" />
                        <span className="truncate">{t[item.labelKey]}</span>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            )}
          </li>
        );
      })}
    </ul>
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

  const [customModules, setCustomModules] = useState<Set<string> | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);

  useEffect(() => {
    if (!profile) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- clearing derived state when the profile isn't loaded yet
      setCustomModules(null);
      return;
    }
    supabase
      .from("profile_module_grants")
      .select("module_href")
      .eq("profile_id", profile.id)
      .then(({ data }) => {
        setCustomModules(
          data && data.length > 0
            ? new Set(data.map((r) => r.module_href))
            : null
        );
      });
  }, [profile]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- closing the mobile drawer when navigation happens (e.g. browser back/forward)
    setDrawerOpen(false);
  }, [routerLocation.pathname]);

  const visibleItems = NAV_ITEMS.filter((item) => {
    // Home always shows — it's where the pending-approval message lives
    // for a session with no profile yet. Everything else needs a profile.
    if (item.href === "/") return true;
    if (!profile) return false;
    const allowed = customModules ?? roleDefaultHrefs(profile.role);
    return allowed.has(item.href);
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
          <NavList items={visibleItems} activePath={routerLocation.pathname} />
        </nav>

        <div className="flex flex-1 flex-col">
          <header className="flex h-14 shrink-0 items-center justify-between gap-2 border-b border-zinc-200 bg-white px-4 dark:border-zinc-800 dark:bg-zinc-900">
            <div className="flex min-w-0 items-center gap-2">
              <button
                type="button"
                onClick={() => setDrawerOpen(true)}
                aria-label={t.openMenu}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-zinc-300 md:hidden dark:border-zinc-700"
              >
                <Menu className="h-4 w-4" />
              </button>
              <h1 className="text-fluffy-dark min-w-0 truncate text-base font-semibold dark:text-zinc-50">
                <span className="hidden sm:inline">
                  {activeLocationName ? `${activeLocationName} — ` : ""}
                </span>
                {title ?? t.appName}
              </h1>
            </div>
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
              <div className="hidden md:block">
                <LanguageToggle />
              </div>
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

          <main className="flex flex-1 flex-col overflow-y-auto">
            {children}
          </main>
        </div>
      </div>

      <MobileDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        items={visibleItems}
        activePath={routerLocation.pathname}
      />
    </div>
  );
}

function MobileDrawer({
  open,
  onClose,
  items,
  activePath,
}: {
  open: boolean;
  onClose: () => void;
  items: NavItem[];
  activePath: string;
}) {
  const { t } = useLocale();

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-50 bg-black/50 md:hidden"
          onClick={onClose}
        />
      )}
      <nav
        className={`fixed inset-y-0 start-0 z-50 flex w-72 max-w-[85vw] flex-col bg-white shadow-xl transition-transform duration-200 md:hidden dark:bg-zinc-900 ${
          open ? "translate-x-0" : "-translate-x-full rtl:translate-x-full"
        }`}
      >
        <div className="flex h-14 shrink-0 items-center justify-between gap-2 border-b border-zinc-200 px-4 dark:border-zinc-800">
          <div className="flex min-w-0 items-center gap-2">
            <span className="bg-fluffy-orange flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-white">
              <ChefHat className="h-5 w-5" />
            </span>
            <span className="text-fluffy-dark truncate text-lg font-semibold dark:text-zinc-50">
              {t.appName}
            </span>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t.closeModal}
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md text-zinc-500"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        <NavList items={items} activePath={activePath} onNavigate={onClose} />
        <div className="shrink-0 border-t border-zinc-200 p-3 dark:border-zinc-800">
          <LanguageToggle />
        </div>
      </nav>
    </>
  );
}

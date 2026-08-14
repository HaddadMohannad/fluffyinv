import type { LucideIcon } from "lucide-react";
import {
  Home,
  Package,
  ShoppingCart,
  Upload,
  PackagePlus,
  Truck,
  ArrowLeftRight,
  Factory,
  CalendarCheck,
  Bell,
  Building,
  Building2,
  Calculator,
  TrendingDown,
  Wallet,
  ClipboardList,
  Heart,
  Trash2,
  Settings2,
  Settings,
  ListChecks,
  ShieldCheck,
  Wrench,
  Gauge,
  UserCog,
  Users,
  PackageSearch,
  GitCompare,
  UtensilsCrossed,
  PlusCircle,
  Tags,
  FolderTree,
  Layers,
} from "lucide-react";
import { dictionary } from "@/lib/i18n/dictionary";

export type Role =
  "admin" | "branch_manager" | "warehouse_staff" | "accountant" | "inspector";

export type NavItem = {
  href: string;
  labelKey: keyof (typeof dictionary)["en"];
  icon: LucideIcon;
  roles?: Role[];
};

export const NAV_ITEMS: NavItem[] = [
  { href: "/", labelKey: "home", icon: Home },
  {
    href: "/inventory",
    labelKey: "inventory",
    icon: Package,
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  { href: "/sales", labelKey: "sales", icon: ShoppingCart },
  {
    href: "/import",
    labelKey: "import",
    icon: Upload,
    roles: ["admin", "accountant"],
  },
  {
    href: "/opening-stock",
    labelKey: "openingStock",
    icon: PackagePlus,
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  {
    href: "/purchase",
    labelKey: "purchase",
    icon: Truck,
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  {
    href: "/transfer",
    labelKey: "transfer",
    icon: ArrowLeftRight,
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  {
    href: "/production",
    labelKey: "production",
    icon: Factory,
    roles: ["admin", "warehouse_staff"],
  },
  {
    href: "/daily-closing",
    labelKey: "dailyClosing",
    icon: CalendarCheck,
    roles: ["admin", "accountant", "branch_manager"],
  },
  {
    href: "/alerts",
    labelKey: "alerts",
    icon: Bell,
    roles: ["admin", "accountant"],
  },
  {
    href: "/suppliers",
    labelKey: "suppliers",
    icon: Building2,
    roles: ["admin", "accountant", "branch_manager"],
  },
  {
    href: "/accountant",
    labelKey: "accountantDashboard",
    icon: Calculator,
    roles: ["admin", "accountant"],
  },
  {
    href: "/consumption",
    labelKey: "consumption",
    icon: TrendingDown,
    roles: ["admin", "branch_manager", "warehouse_staff"],
  },
  {
    href: "/cash-expenses",
    labelKey: "cashExpenses",
    icon: Wallet,
    roles: ["admin", "accountant", "branch_manager"],
  },
  {
    href: "/stocktake",
    labelKey: "stocktake",
    icon: ClipboardList,
    roles: ["admin", "branch_manager"],
  },
  {
    href: "/hospitality",
    labelKey: "hospitality",
    icon: Heart,
    roles: ["admin", "branch_manager"],
  },
  {
    href: "/branches",
    labelKey: "branches",
    icon: Building,
    roles: ["admin"],
  },
  {
    href: "/waste",
    labelKey: "waste",
    icon: Trash2,
    roles: ["admin", "branch_manager"],
  },
  {
    href: "/lookup-lists",
    labelKey: "lookupLists",
    icon: Settings2,
    roles: ["admin"],
  },
  {
    href: "/audit-criteria",
    labelKey: "auditCriteria",
    icon: ListChecks,
    roles: ["admin"],
  },
  {
    href: "/audit-entry",
    labelKey: "qualityAudit",
    icon: ShieldCheck,
    roles: ["admin", "branch_manager", "inspector"],
  },
  {
    href: "/corrective-actions",
    labelKey: "correctiveActionsTitle",
    icon: Wrench,
    roles: ["admin", "branch_manager", "inspector"],
  },
  {
    href: "/quality-dashboard",
    labelKey: "qualityDashboardTitle",
    icon: Gauge,
    roles: ["admin", "accountant", "branch_manager", "inspector"],
  },
  {
    href: "/audit-access",
    labelKey: "auditAccessTitle",
    icon: UserCog,
    roles: ["admin"],
  },
  {
    href: "/unmatched-items",
    labelKey: "unmatchedItemsNavLabel",
    icon: PackageSearch,
    roles: ["admin"],
  },
  {
    href: "/users",
    labelKey: "usersNavLabel",
    icon: Users,
    roles: ["admin"],
  },
  {
    href: "/settings",
    labelKey: "settingsTitle",
    icon: Settings,
    roles: ["admin"],
  },
  {
    href: "/branch-comparison",
    labelKey: "branchComparison",
    icon: GitCompare,
    roles: ["admin", "accountant"],
  },
  {
    href: "/product-categories",
    labelKey: "productCategories",
    icon: FolderTree,
    roles: ["admin"],
  },
  {
    href: "/menu",
    labelKey: "menu",
    icon: UtensilsCrossed,
    roles: ["admin"],
  },
  {
    href: "/add-ons",
    labelKey: "addons",
    icon: PlusCircle,
    roles: ["admin"],
  },
  {
    href: "/addon-categories",
    labelKey: "addonCategories",
    icon: Tags,
    roles: ["admin"],
  },
  {
    href: "/product-groups",
    labelKey: "productGroups",
    icon: Layers,
    roles: ["admin"],
  },
];

// Every module a role sees out of the box, before any per-user
// customization in profile_module_grants narrows or widens it.
export function roleDefaultHrefs(role: Role): Set<string> {
  const hrefs = new Set<string>();
  for (const item of NAV_ITEMS) {
    if (!item.roles || item.roles.includes(role)) hrefs.add(item.href);
  }
  return hrefs;
}

export type NavGroup = {
  key: string;
  labelKey: keyof (typeof dictionary)["en"];
  icon: LucideIcon;
  // Order here is the order items render in when the group is expanded.
  hrefs: string[];
};

// Related modules collapsed under one expandable entry so the nav
// doesn't read as one long flat list. An item not listed in any group's
// hrefs renders at the top level as before.
export const NAV_GROUPS: NavGroup[] = [
  {
    key: "quality-audits",
    labelKey: "auditGroupLabel",
    icon: ShieldCheck,
    hrefs: [
      "/audit-entry",
      "/corrective-actions",
      "/quality-dashboard",
      "/audit-criteria",
      "/audit-access",
    ],
  },
  {
    key: "inventory-ops",
    labelKey: "inventoryGroupLabel",
    icon: Package,
    hrefs: [
      "/inventory",
      "/opening-stock",
      "/purchase",
      "/transfer",
      "/production",
      "/stocktake",
      "/waste",
      "/hospitality",
      "/consumption",
    ],
  },
  {
    key: "menu-builder",
    labelKey: "menuBuilderGroupLabel",
    icon: UtensilsCrossed,
    hrefs: [
      "/product-categories",
      "/menu",
      "/add-ons",
      "/addon-categories",
      "/product-groups",
    ],
  },
  {
    key: "finance",
    labelKey: "financeGroupLabel",
    icon: Calculator,
    hrefs: [
      "/daily-closing",
      "/cash-expenses",
      "/accountant",
      "/suppliers",
      "/alerts",
      "/branch-comparison",
    ],
  },
  {
    key: "admin-settings",
    labelKey: "adminGroupLabel",
    icon: Settings2,
    hrefs: [
      "/branches",
      "/lookup-lists",
      "/unmatched-items",
      "/users",
      "/settings",
    ],
  },
];

export type NavNode =
  | { kind: "item"; item: NavItem }
  | { kind: "group"; group: NavGroup; items: NavItem[] };

// Folds a flat, already role/grant-filtered item list into top-level
// items plus grouped runs, in the position of each group's first member
// — so the overall order still matches NAV_ITEMS. A group never appears
// with zero items since every item it contains came from the input list.
export function groupNavItems(items: NavItem[]): NavNode[] {
  const byHref = new Map(items.map((item) => [item.href, item]));
  const rendered = new Set<string>();
  const nodes: NavNode[] = [];

  for (const item of items) {
    const group = NAV_GROUPS.find((g) => g.hrefs.includes(item.href));
    if (!group) {
      nodes.push({ kind: "item", item });
      continue;
    }
    if (rendered.has(group.key)) continue;
    rendered.add(group.key);
    const groupItems = group.hrefs
      .map((href) => byHref.get(href))
      .filter((i): i is NavItem => Boolean(i));
    nodes.push({ kind: "group", group, items: groupItems });
  }

  return nodes;
}

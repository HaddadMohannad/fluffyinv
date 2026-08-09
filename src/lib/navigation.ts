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
  ListChecks,
  ShieldCheck,
  Wrench,
  Gauge,
  UserCog,
  Users,
  PackageSearch,
} from "lucide-react";
import { dictionary } from "@/lib/i18n/dictionary";

export type NavItem = {
  href: string;
  labelKey: keyof (typeof dictionary)["en"];
  icon: LucideIcon;
  roles?: Array<
    | "admin"
    | "branch_manager"
    | "warehouse_staff"
    | "accountant"
    | "inspector"
  >;
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
];

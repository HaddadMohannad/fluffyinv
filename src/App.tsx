import { lazy, Suspense } from "react";
import { Routes, Route } from "react-router";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import { AppShell } from "@/components/AppShell";
import { useLocale } from "@/lib/i18n/LocaleContext";
import { LoginPage } from "@/pages/LoginPage";
import { ResetPasswordPage } from "@/pages/ResetPasswordPage";
import { HomePage } from "@/pages/HomePage";
import { ImportPage } from "@/pages/ImportPage";
import { SalesDashboardPage } from "@/pages/SalesDashboardPage";
import { OpeningStockPage } from "@/pages/OpeningStockPage";
import { PurchasePage } from "@/pages/PurchasePage";
import { TransferPage } from "@/pages/TransferPage";
import { StocktakePage } from "@/pages/StocktakePage";
import { HospitalityPage } from "@/pages/HospitalityPage";
import { BranchManagementPage } from "@/pages/BranchManagementPage";
import { WastePage } from "@/pages/WastePage";
import { LookupListsPage } from "@/pages/LookupListsPage";
import { AuditCriteriaPage } from "@/pages/AuditCriteriaPage";
import { AuditEntryPage } from "@/pages/AuditEntryPage";
import { CorrectiveActionsPage } from "@/pages/CorrectiveActionsPage";
import { AuditAccessPage } from "@/pages/AuditAccessPage";
import { VisitDetailPage } from "@/pages/VisitDetailPage";
import { InventoryPage } from "@/pages/InventoryPage";
import { ProductionPage } from "@/pages/ProductionPage";
import { DailyClosingPage } from "@/pages/DailyClosingPage";
import { AlertsPage } from "@/pages/AlertsPage";
import { SuppliersPage } from "@/pages/SuppliersPage";
import { AccountantDashboardPage } from "@/pages/AccountantDashboardPage";
import { ConsumptionReportPage } from "@/pages/ConsumptionReportPage";
import { CashAndExpensesPage } from "@/pages/CashAndExpensesPage";
import { ProductAliasesPage } from "@/pages/ProductAliasesPage";
import { UsersPage } from "@/pages/UsersPage";
import { SettingsPage } from "@/pages/SettingsPage";
import { BranchComparisonPage } from "@/pages/BranchComparisonPage";
import { MenuPage } from "@/pages/MenuPage";
import { AddOnsPage } from "@/pages/AddOnsPage";
import { AddOnCategoriesPage } from "@/pages/AddOnCategoriesPage";

// Charting (recharts) adds significant weight — only load it for people
// who actually open the quality dashboard.
const QualityDashboardPage = lazy(() =>
  import("@/pages/QualityDashboardPage").then((m) => ({
    default: m.QualityDashboardPage,
  }))
);

function PageLoadingFallback() {
  const { t } = useLocale();
  return (
    <div className="flex flex-1 items-center justify-center p-6 text-sm text-zinc-500">
      {t.loadingSales}
    </div>
  );
}

export function App() {
  const { t } = useLocale();

  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/reset-password" element={<ResetPasswordPage />} />
      <Route element={<ProtectedRoute />}>
        <Route
          path="/"
          element={
            <AppShell title={t.home}>
              <HomePage />
            </AppShell>
          }
        />
        <Route
          path="/sales"
          element={
            <AppShell title={t.salesDashboardTitle}>
              <SalesDashboardPage />
            </AppShell>
          }
        />
        <Route
          path="/import"
          element={
            <AppShell title={t.importTitle}>
              <ImportPage />
            </AppShell>
          }
        />
        <Route
          path="/opening-stock"
          element={
            <AppShell title={t.openingStockTitle}>
              <OpeningStockPage />
            </AppShell>
          }
        />
        <Route
          path="/purchase"
          element={
            <AppShell title={t.purchaseTitle}>
              <PurchasePage />
            </AppShell>
          }
        />
        <Route
          path="/transfer"
          element={
            <AppShell title={t.transferTitle}>
              <TransferPage />
            </AppShell>
          }
        />
        <Route
          path="/stocktake"
          element={
            <AppShell title={t.stocktakeTitle}>
              <StocktakePage />
            </AppShell>
          }
        />
        <Route
          path="/hospitality"
          element={
            <AppShell title={t.hospitalityTitle}>
              <HospitalityPage />
            </AppShell>
          }
        />
        <Route
          path="/branches"
          element={
            <AppShell title={t.branchesTitle}>
              <BranchManagementPage />
            </AppShell>
          }
        />
        <Route
          path="/waste"
          element={
            <AppShell title={t.wasteTitle}>
              <WastePage />
            </AppShell>
          }
        />
        <Route
          path="/lookup-lists"
          element={
            <AppShell title={t.lookupListsTitle}>
              <LookupListsPage />
            </AppShell>
          }
        />
        <Route
          path="/audit-criteria"
          element={
            <AppShell title={t.auditCriteriaTitle}>
              <AuditCriteriaPage />
            </AppShell>
          }
        />
        <Route
          path="/audit-entry"
          element={
            <AppShell title={t.auditEntryTitle}>
              <AuditEntryPage />
            </AppShell>
          }
        />
        <Route
          path="/corrective-actions"
          element={
            <AppShell title={t.correctiveActionsTitle}>
              <CorrectiveActionsPage />
            </AppShell>
          }
        />
        <Route
          path="/quality-dashboard"
          element={
            <AppShell title={t.qualityDashboardTitle}>
              <Suspense fallback={<PageLoadingFallback />}>
                <QualityDashboardPage />
              </Suspense>
            </AppShell>
          }
        />
        <Route
          path="/audit-access"
          element={
            <AppShell title={t.auditAccessTitle}>
              <AuditAccessPage />
            </AppShell>
          }
        />
        <Route
          path="/audit-visit/:id"
          element={
            <AppShell title={t.visitDetailsTitle}>
              <VisitDetailPage />
            </AppShell>
          }
        />
        <Route
          path="/inventory"
          element={
            <AppShell title={t.inventoryTitle}>
              <InventoryPage />
            </AppShell>
          }
        />
        <Route
          path="/production"
          element={
            <AppShell title={t.productionTitle}>
              <ProductionPage />
            </AppShell>
          }
        />
        <Route
          path="/daily-closing"
          element={
            <AppShell title={t.dailyClosingTitle}>
              <DailyClosingPage />
            </AppShell>
          }
        />
        <Route
          path="/alerts"
          element={
            <AppShell title={t.alertsTitle}>
              <AlertsPage />
            </AppShell>
          }
        />
        <Route
          path="/suppliers"
          element={
            <AppShell title={t.suppliersTitle}>
              <SuppliersPage />
            </AppShell>
          }
        />
        <Route
          path="/accountant"
          element={
            <AppShell title={t.accountantDashboardTitle}>
              <AccountantDashboardPage />
            </AppShell>
          }
        />
        <Route
          path="/consumption"
          element={
            <AppShell title={t.consumptionReportTitle}>
              <ConsumptionReportPage />
            </AppShell>
          }
        />
        <Route
          path="/cash-expenses"
          element={
            <AppShell title={t.cashAndExpensesTitle}>
              <CashAndExpensesPage />
            </AppShell>
          }
        />
        <Route
          path="/unmatched-items"
          element={
            <AppShell title={t.unmatchedItemsTitle}>
              <ProductAliasesPage />
            </AppShell>
          }
        />
        <Route
          path="/users"
          element={
            <AppShell title={t.usersTitle}>
              <UsersPage />
            </AppShell>
          }
        />
        <Route
          path="/settings"
          element={
            <AppShell title={t.settingsTitle}>
              <SettingsPage />
            </AppShell>
          }
        />
        <Route
          path="/branch-comparison"
          element={
            <AppShell title={t.branchComparisonTitle}>
              <BranchComparisonPage />
            </AppShell>
          }
        />
        <Route
          path="/menu"
          element={
            <AppShell title={t.menuTitle}>
              <MenuPage />
            </AppShell>
          }
        />
        <Route
          path="/add-ons"
          element={
            <AppShell title={t.addonsTitle}>
              <AddOnsPage />
            </AppShell>
          }
        />
        <Route
          path="/addon-categories"
          element={
            <AppShell title={t.addonCategoriesTitle}>
              <AddOnCategoriesPage />
            </AppShell>
          }
        />
      </Route>
    </Routes>
  );
}

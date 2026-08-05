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
import { InventoryPage } from "@/pages/InventoryPage";
import { ProductionPage } from "@/pages/ProductionPage";
import { DailyClosingPage } from "@/pages/DailyClosingPage";
import { AlertsPage } from "@/pages/AlertsPage";
import { SuppliersPage } from "@/pages/SuppliersPage";
import { AccountantDashboardPage } from "@/pages/AccountantDashboardPage";
import { ConsumptionReportPage } from "@/pages/ConsumptionReportPage";
import { CashAndExpensesPage } from "@/pages/CashAndExpensesPage";
import { ProductAliasesPage } from "@/pages/ProductAliasesPage";
import { SettingsPage } from "@/pages/SettingsPage";

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
          path="/settings"
          element={
            <AppShell title={t.settingsTitle}>
              <SettingsPage />
            </AppShell>
          }
        />
      </Route>
    </Routes>
  );
}

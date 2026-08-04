import { Routes, Route } from "react-router-dom";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import { AppShell } from "@/components/AppShell";
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

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/reset-password" element={<ResetPasswordPage />} />
      <Route element={<ProtectedRoute />}>
        <Route
          path="/"
          element={
            <AppShell>
              <HomePage />
            </AppShell>
          }
        />
        <Route
          path="/sales"
          element={
            <AppShell>
              <SalesDashboardPage />
            </AppShell>
          }
        />
        <Route
          path="/import"
          element={
            <AppShell>
              <ImportPage />
            </AppShell>
          }
        />
        <Route
          path="/opening-stock"
          element={
            <AppShell>
              <OpeningStockPage />
            </AppShell>
          }
        />
        <Route
          path="/purchase"
          element={
            <AppShell>
              <PurchasePage />
            </AppShell>
          }
        />
        <Route
          path="/transfer"
          element={
            <AppShell>
              <TransferPage />
            </AppShell>
          }
        />
        <Route
          path="/stocktake"
          element={
            <AppShell>
              <StocktakePage />
            </AppShell>
          }
        />
        <Route
          path="/hospitality"
          element={
            <AppShell>
              <HospitalityPage />
            </AppShell>
          }
        />
        <Route
          path="/waste"
          element={
            <AppShell>
              <WastePage />
            </AppShell>
          }
        />
        <Route
          path="/lookup-lists"
          element={
            <AppShell>
              <LookupListsPage />
            </AppShell>
          }
        />
        <Route
          path="/inventory"
          element={
            <AppShell>
              <InventoryPage />
            </AppShell>
          }
        />
        <Route
          path="/production"
          element={
            <AppShell>
              <ProductionPage />
            </AppShell>
          }
        />
        <Route
          path="/daily-closing"
          element={
            <AppShell>
              <DailyClosingPage />
            </AppShell>
          }
        />
        <Route
          path="/alerts"
          element={
            <AppShell>
              <AlertsPage />
            </AppShell>
          }
        />
        <Route
          path="/suppliers"
          element={
            <AppShell>
              <SuppliersPage />
            </AppShell>
          }
        />
        <Route
          path="/accountant"
          element={
            <AppShell>
              <AccountantDashboardPage />
            </AppShell>
          }
        />
        <Route
          path="/consumption"
          element={
            <AppShell>
              <ConsumptionReportPage />
            </AppShell>
          }
        />
        <Route
          path="/cash-expenses"
          element={
            <AppShell>
              <CashAndExpensesPage />
            </AppShell>
          }
        />
      </Route>
    </Routes>
  );
}

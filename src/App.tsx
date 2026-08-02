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
      </Route>
    </Routes>
  );
}

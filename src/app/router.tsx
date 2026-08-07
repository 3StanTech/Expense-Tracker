import { createBrowserRouter, Navigate } from 'react-router-dom'
import { AppShell } from '@/components/layout/AppShell'
import { RequireAuth } from '@/features/auth/RequireAuth'
import {
  AuthCallbackPage,
  ForgotPasswordPage,
  LoginPage,
  ResetPasswordPage,
  SignupPage,
} from '@/features/auth/AuthPages'
import { DashboardPage } from '@/features/dashboard/DashboardPage'
import { AccountsPage } from '@/features/accounts/AccountsPage'
import { TransactionsPage } from '@/features/transactions/TransactionsPage'
import { BudgetsPage } from '@/features/budgets/BudgetsPage'
import { RecurringPage } from '@/features/recurring/RecurringPage'
import { GoalsPage } from '@/features/goals/GoalsPage'
import { DebtsPage } from '@/features/debts/DebtsPage'
import { ReportsPage } from '@/features/reports/ReportsPage'
import { SettingsPage } from '@/features/settings/SettingsPage'
import { RouteErrorBoundary } from '@/app/RouteErrorBoundary'

function Protected({ children }: { children: React.ReactNode }) {
  return <RequireAuth>{children}</RequireAuth>
}

export const router = createBrowserRouter([
  { path: '/', element: <Navigate to="/app" replace /> },
  { path: '/login', element: <LoginPage />, errorElement: <RouteErrorBoundary /> },
  { path: '/signup', element: <SignupPage />, errorElement: <RouteErrorBoundary /> },
  {
    path: '/forgot-password',
    element: <ForgotPasswordPage />,
    errorElement: <RouteErrorBoundary />,
  },
  { path: '/reset-password', element: <ResetPasswordPage />, errorElement: <RouteErrorBoundary /> },
  { path: '/auth/callback', element: <AuthCallbackPage />, errorElement: <RouteErrorBoundary /> },
  {
    path: '/app',
    element: (
      <Protected>
        <AppShell />
      </Protected>
    ),
    errorElement: <RouteErrorBoundary />,
    children: [
      { index: true, element: <DashboardPage /> },
      { path: 'transactions', element: <TransactionsPage /> },
      { path: 'accounts', element: <AccountsPage /> },
      { path: 'budgets', element: <BudgetsPage /> },
      { path: 'recurring', element: <RecurringPage /> },
      { path: 'goals', element: <GoalsPage /> },
      { path: 'debts', element: <DebtsPage /> },
      { path: 'reports', element: <ReportsPage /> },
      { path: 'settings', element: <SettingsPage /> },
    ],
  },
  { path: '*', element: <Navigate to="/app" replace /> },
])

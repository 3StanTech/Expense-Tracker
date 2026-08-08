import { getSupabase } from '@/lib/supabase'
import {
  mapAccount,
  mapBudget,
  mapCategory,
  mapContribution,
  mapDebt,
  mapGoal,
  mapProfile,
  mapRecurring,
  mapTransaction,
} from '@/lib/mappers'
import type {
  Account,
  Budget,
  Category,
  Debt,
  GoalContribution,
  Profile,
  RecurringRule,
  SavingsGoal,
  Transaction,
  MonthlyCashFlowRow,
  CategorySpendRow,
  BudgetActualRow,
  DebtBalanceRow,
  NetWorthPoint,
  AccountBalance,
} from '@/types/domain'
import type { Database } from '@/types/database'
import { getErrorMessage } from '@/lib/errors'
import { monthDateBounds } from '@/lib/dates'

async function requireUserId(): Promise<string> {
  const { data, error } = await getSupabase().auth.getUser()
  if (error) throw new Error(getErrorMessage(error, 'Session expired'))
  if (!data.user) throw new Error('Not authenticated')
  return data.user.id
}

function throwOnError(error: { message: string } | null, fallback: string): void {
  if (error) throw new Error(getErrorMessage(error, fallback))
}

function requireData<T>(data: T | null, fallback: string): T {
  if (data == null) throw new Error(fallback)
  return data
}

// --- Profile ---
export async function fetchProfile(): Promise<Profile | null> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('profiles')
    .select('*')
    .eq('id', uid)
    .maybeSingle()
  throwOnError(error, 'Failed to load profile')
  return data ? mapProfile(data) : null
}

export async function updateProfile(displayName: string | null): Promise<Profile> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('profiles')
    .update({ display_name: displayName })
    .eq('id', uid)
    .select('*')
    .single()
  throwOnError(error, 'Failed to update profile')
  return mapProfile(requireData(data, 'Profile not found'))
}

// --- Categories ---
export async function fetchCategories(): Promise<Category[]> {
  const { data, error } = await getSupabase()
    .from('categories')
    .select('*')
    .eq('is_archived', false)
    .order('name')
  throwOnError(error, 'Failed to load categories')
  return (data ?? []).map(mapCategory)
}

export async function createCategory(input: {
  name: string
  kind: 'income' | 'expense'
  color: string | null
}): Promise<Category> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('categories')
    .insert({
      user_id: uid,
      name: input.name,
      kind: input.kind,
      color: input.color,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to create category')
  return mapCategory(requireData(data, 'Category not found'))
}

export async function archiveCategory(id: string): Promise<void> {
  const { error } = await getSupabase()
    .from('categories')
    .update({ is_archived: true })
    .eq('id', id)
  throwOnError(error, 'Failed to archive category')
}

// --- Accounts ---
export async function fetchAccounts(): Promise<Account[]> {
  const { data, error } = await getSupabase()
    .from('accounts')
    .select('*')
    .eq('is_archived', false)
    .order('name')
  throwOnError(error, 'Failed to load accounts')
  return (data ?? []).map(mapAccount)
}

export async function createAccount(input: {
  name: string
  type: Account['type']
  openingBalanceMinor: number
  notes: string | null
}): Promise<Account> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('accounts')
    .insert({
      user_id: uid,
      name: input.name,
      type: input.type,
      opening_balance_minor: input.openingBalanceMinor,
      notes: input.notes,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to create account')
  return mapAccount(requireData(data, 'Account not found'))
}

export async function updateAccount(
  id: string,
  input: Partial<{
    name: string
    type: Account['type']
    openingBalanceMinor: number
    notes: string | null
    isArchived: boolean
  }>,
): Promise<Account> {
  const payload: Database['public']['Tables']['accounts']['Update'] = {}
  if (input.name !== undefined) payload.name = input.name
  if (input.type !== undefined) payload.type = input.type
  if (input.openingBalanceMinor !== undefined)
    payload.opening_balance_minor = input.openingBalanceMinor
  if (input.notes !== undefined) payload.notes = input.notes
  if (input.isArchived !== undefined) payload.is_archived = input.isArchived

  const { data, error } = await getSupabase()
    .from('accounts')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single()
  throwOnError(error, 'Failed to update account')
  return mapAccount(requireData(data, 'Account not found'))
}

export async function fetchAccountBalances(): Promise<AccountBalance[]> {
  const { data, error } = await getSupabase().from('v_account_balances').select('*')
  throwOnError(error, 'Failed to load balances')
  return (data ?? []).map((r) => ({
    accountId: r.account_id!,
    balanceMinor: Number(r.balance_minor ?? 0),
  }))
}

// --- Transactions ---
export async function fetchTransactions(filters?: {
  month?: string
  accountId?: string
}): Promise<Transaction[]> {
  let q = getSupabase()
    .from('transactions')
    .select('*')
    .order('occurred_on', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(500)

  if (filters?.accountId) q = q.eq('account_id', filters.accountId)
  if (filters?.month) {
    // Calendar-string bounds (inclusive start, exclusive next month) — no UTC conversion.
    const { start, endExclusive } = monthDateBounds(filters.month)
    q = q.gte('occurred_on', start).lt('occurred_on', endExclusive)
  }

  const { data, error } = await q
  throwOnError(error, 'Failed to load transactions')
  return (data ?? []).map(mapTransaction)
}

export async function createTransaction(input: {
  kind: Transaction['kind']
  status: Transaction['status']
  amountMinor: number
  occurredOn: string
  accountId: string
  transferAccountId: string | null
  categoryId: string | null
  payee: string | null
  notes: string | null
}): Promise<Transaction> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('transactions')
    .insert({
      user_id: uid,
      kind: input.kind,
      status: input.status,
      amount_minor: input.amountMinor,
      occurred_on: input.occurredOn,
      account_id: input.accountId,
      transfer_account_id: input.transferAccountId,
      category_id: input.categoryId,
      payee: input.payee,
      notes: input.notes,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to create transaction')
  return mapTransaction(requireData(data, 'Transaction not found'))
}

export async function updateTransaction(
  id: string,
  input: {
    kind: Transaction['kind']
    status: Transaction['status']
    amountMinor: number
    occurredOn: string
    accountId: string
    transferAccountId: string | null
    categoryId: string | null
    payee: string | null
    notes: string | null
  },
): Promise<Transaction> {
  const { data, error } = await getSupabase()
    .from('transactions')
    .update({
      kind: input.kind,
      status: input.status,
      amount_minor: input.amountMinor,
      occurred_on: input.occurredOn,
      account_id: input.accountId,
      transfer_account_id: input.transferAccountId,
      category_id: input.categoryId,
      payee: input.payee,
      notes: input.notes,
    })
    .eq('id', id)
    .select('*')
    .single()
  throwOnError(error, 'Failed to update transaction')
  return mapTransaction(requireData(data, 'Transaction not found'))
}

export async function deleteTransaction(id: string): Promise<void> {
  const { error } = await getSupabase().from('transactions').delete().eq('id', id)
  throwOnError(error, 'Failed to delete transaction')
}

// --- Budgets ---
export async function fetchBudgets(month?: string): Promise<Budget[]> {
  let q = getSupabase().from('budgets').select('*').order('month', { ascending: false })
  if (month) q = q.eq('month', month)
  const { data, error } = await q
  throwOnError(error, 'Failed to load budgets')
  return (data ?? []).map(mapBudget)
}

export async function createBudget(input: {
  categoryId: string
  month: string
  amountMinor: number
}): Promise<Budget> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('budgets')
    .insert({
      user_id: uid,
      category_id: input.categoryId,
      month: input.month,
      amount_minor: input.amountMinor,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to create budget')
  return mapBudget(requireData(data, 'Budget not found'))
}

export async function updateBudget(id: string, amountMinor: number): Promise<Budget> {
  const { data, error } = await getSupabase()
    .from('budgets')
    .update({ amount_minor: amountMinor })
    .eq('id', id)
    .select('*')
    .single()
  throwOnError(error, 'Failed to update budget')
  return mapBudget(requireData(data, 'Budget not found'))
}

export async function deleteBudget(id: string): Promise<void> {
  const { error } = await getSupabase().from('budgets').delete().eq('id', id)
  throwOnError(error, 'Failed to delete budget')
}

export async function fetchBudgetActuals(month?: string): Promise<BudgetActualRow[]> {
  let q = getSupabase().from('v_budget_actuals').select('*')
  if (month) q = q.eq('month', month)
  const { data, error } = await q
  throwOnError(error, 'Failed to load budget actuals')
  return (data ?? []).map((r) => ({
    budgetId: r.budget_id!,
    categoryId: r.category_id!,
    categoryName: r.category_name!,
    month: r.month!,
    budgetMinor: Number(r.budget_minor ?? 0),
    spentMinor: Number(r.spent_minor ?? 0),
  }))
}

// --- Recurring ---
export async function fetchRecurringRules(): Promise<RecurringRule[]> {
  const { data, error } = await getSupabase().from('recurring_rules').select('*').order('name')
  throwOnError(error, 'Failed to load recurring rules')
  return (data ?? []).map(mapRecurring)
}

export async function createRecurringRule(input: {
  name: string
  kind: RecurringRule['kind']
  amountMinor: number
  accountId: string
  transferAccountId: string | null
  categoryId: string | null
  payee: string | null
  notes: string | null
  frequency: RecurringRule['frequency']
  intervalCount: number
  startDate: string
  endDate: string | null
  status: RecurringRule['status']
}): Promise<RecurringRule> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('recurring_rules')
    .insert({
      user_id: uid,
      name: input.name,
      kind: input.kind,
      amount_minor: input.amountMinor,
      account_id: input.accountId,
      transfer_account_id: input.transferAccountId,
      category_id: input.categoryId,
      payee: input.payee,
      notes: input.notes,
      frequency: input.frequency,
      interval_count: input.intervalCount,
      start_date: input.startDate,
      end_date: input.endDate,
      status: input.status,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to create recurring rule')
  return mapRecurring(requireData(data, 'Recurring rule not found'))
}

export async function updateRecurringRule(
  id: string,
  patch: Partial<{
    name: string
    status: RecurringRule['status']
    amountMinor: number
    endDate: string | null
  }>,
): Promise<RecurringRule> {
  const payload: Database['public']['Tables']['recurring_rules']['Update'] = {}
  if (patch.name !== undefined) payload.name = patch.name
  if (patch.status !== undefined) payload.status = patch.status
  if (patch.amountMinor !== undefined) payload.amount_minor = patch.amountMinor
  if (patch.endDate !== undefined) payload.end_date = patch.endDate

  const { data, error } = await getSupabase()
    .from('recurring_rules')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single()
  throwOnError(error, 'Failed to update recurring rule')
  return mapRecurring(requireData(data, 'Recurring rule not found'))
}

export async function deleteRecurringRule(id: string): Promise<void> {
  const { error } = await getSupabase().from('recurring_rules').delete().eq('id', id)
  throwOnError(error, 'Failed to delete recurring rule')
}

export async function materializeRecurring(asOf?: string): Promise<number> {
  const { data, error } = await getSupabase().rpc('materialize_due_recurring_entries', {
    p_as_of: asOf ?? null,
  })
  throwOnError(error, 'Failed to materialize recurring entries')
  return Number(data ?? 0)
}

// --- Goals ---
export async function fetchGoals(): Promise<SavingsGoal[]> {
  const { data, error } = await getSupabase()
    .from('savings_goals')
    .select('*')
    .eq('is_archived', false)
    .order('name')
  throwOnError(error, 'Failed to load goals')
  return (data ?? []).map(mapGoal)
}

export async function createGoal(input: {
  name: string
  targetAmountMinor: number
  targetDate: string | null
  notes: string | null
}): Promise<SavingsGoal> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('savings_goals')
    .insert({
      user_id: uid,
      name: input.name,
      target_amount_minor: input.targetAmountMinor,
      target_date: input.targetDate,
      notes: input.notes,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to create goal')
  return mapGoal(requireData(data, 'Goal not found'))
}

export async function updateGoal(
  id: string,
  patch: Partial<{
    name: string
    targetAmountMinor: number
    targetDate: string | null
    notes: string | null
    isArchived: boolean
  }>,
): Promise<SavingsGoal> {
  const payload: Database['public']['Tables']['savings_goals']['Update'] = {}
  if (patch.name !== undefined) payload.name = patch.name
  if (patch.targetAmountMinor !== undefined) payload.target_amount_minor = patch.targetAmountMinor
  if (patch.targetDate !== undefined) payload.target_date = patch.targetDate
  if (patch.notes !== undefined) payload.notes = patch.notes
  if (patch.isArchived !== undefined) payload.is_archived = patch.isArchived

  const { data, error } = await getSupabase()
    .from('savings_goals')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single()
  throwOnError(error, 'Failed to update goal')
  return mapGoal(requireData(data, 'Goal not found'))
}

export async function addContribution(input: {
  goalId: string
  amountMinor: number
  contributedOn: string
  notes: string | null
}): Promise<GoalContribution> {
  const uid = await requireUserId()
  const { data, error } = await getSupabase()
    .from('goal_contributions')
    .insert({
      user_id: uid,
      goal_id: input.goalId,
      amount_minor: input.amountMinor,
      contributed_on: input.contributedOn,
      notes: input.notes,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to add contribution')
  return mapContribution(requireData(data, 'Contribution not found'))
}

// --- Debts ---
export async function fetchDebts(): Promise<Debt[]> {
  const { data, error } = await getSupabase()
    .from('debts')
    .select('*')
    .eq('is_active', true)
    .order('name')
  throwOnError(error, 'Failed to load debts')
  return (data ?? []).map(mapDebt)
}

export async function createDebt(input: {
  name: string
  accountId: string
  interestBps: number
  minimumPaymentMinor: number
  dueDay: number
  notes: string | null
}): Promise<Debt> {
  const uid = await requireUserId()
  // principal_minor is metadata-only (original snapshot). Current balance is the linked account.
  const { data: account, error: accountError } = await getSupabase()
    .from('accounts')
    .select('opening_balance_minor')
    .eq('id', input.accountId)
    .single()
  throwOnError(accountError, 'Failed to load liability account for debt')
  const originalPrincipalMinor = Number(
    requireData(account, 'Liability account not found').opening_balance_minor ?? 0,
  )

  const { data, error } = await getSupabase()
    .from('debts')
    .insert({
      user_id: uid,
      name: input.name,
      account_id: input.accountId,
      principal_minor: originalPrincipalMinor,
      interest_bps: input.interestBps,
      minimum_payment_minor: input.minimumPaymentMinor,
      due_day: input.dueDay,
      notes: input.notes,
    })
    .select('*')
    .single()
  throwOnError(error, 'Failed to create debt')
  return mapDebt(requireData(data, 'Debt not found'))
}

export async function updateDebt(
  id: string,
  patch: Partial<{
    name: string
    interestBps: number
    minimumPaymentMinor: number
    dueDay: number
    notes: string | null
    isActive: boolean
  }>,
): Promise<Debt> {
  const payload: Database['public']['Tables']['debts']['Update'] = {}
  if (patch.name !== undefined) payload.name = patch.name
  if (patch.interestBps !== undefined) payload.interest_bps = patch.interestBps
  if (patch.minimumPaymentMinor !== undefined)
    payload.minimum_payment_minor = patch.minimumPaymentMinor
  if (patch.dueDay !== undefined) payload.due_day = patch.dueDay
  if (patch.notes !== undefined) payload.notes = patch.notes
  if (patch.isActive !== undefined) payload.is_active = patch.isActive

  const { data, error } = await getSupabase()
    .from('debts')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single()
  throwOnError(error, 'Failed to update debt')
  return mapDebt(requireData(data, 'Debt not found'))
}

export async function fetchDebtBalances(): Promise<DebtBalanceRow[]> {
  const { data, error } = await getSupabase().from('v_debt_balances').select('*')
  throwOnError(error, 'Failed to load debt balances')
  return (data ?? []).map((r) => ({
    debtId: r.debt_id!,
    name: r.name!,
    balanceMinor: Number(r.balance_minor ?? 0),
    minimumPaymentMinor: Number(r.minimum_payment_minor ?? 0),
    dueDay: Number(r.due_day ?? 1),
  }))
}

// --- Analytics views ---
export async function fetchMonthlyCashFlow(): Promise<MonthlyCashFlowRow[]> {
  const { data, error } = await getSupabase()
    .from('v_monthly_cash_flow')
    .select('*')
    .order('month', { ascending: true })
  throwOnError(error, 'Failed to load cash flow')
  return (data ?? []).map((r) => ({
    month: r.month!,
    incomeMinor: Number(r.income_minor ?? 0),
    expenseMinor: Number(r.expense_minor ?? 0),
  }))
}

export async function fetchCategorySpending(month: string): Promise<CategorySpendRow[]> {
  const { data, error } = await getSupabase()
    .from('v_category_spending')
    .select('*')
    .eq('month', month)
  throwOnError(error, 'Failed to load category spending')
  return (data ?? []).map((r) => ({
    categoryId: r.category_id!,
    categoryName: r.category_name!,
    amountMinor: Number(r.amount_minor ?? 0),
  }))
}

export async function fetchNetWorthHistory(): Promise<NetWorthPoint[]> {
  const { data, error } = await getSupabase()
    .from('v_net_worth_history')
    .select('*')
    .order('as_of', { ascending: true })
  throwOnError(error, 'Failed to load net worth history')
  return (data ?? []).map((r) => ({
    asOf: r.as_of!,
    netWorthMinor: Number(r.net_worth_minor ?? 0),
  }))
}

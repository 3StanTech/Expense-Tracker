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
} from '@/types/domain'
import type { Database } from '@/types/database'

type Tables = Database['public']['Tables']

export function mapProfile(row: Tables['profiles']['Row']): Profile {
  return {
    id: row.id,
    displayName: row.display_name,
    currency: row.currency as Profile['currency'],
    locale: row.locale as Profile['locale'],
    timezone: row.timezone as Profile['timezone'],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function mapCategory(row: Tables['categories']['Row']): Category {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    kind: row.kind,
    color: row.color,
    icon: row.icon,
    isArchived: row.is_archived,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function mapAccount(row: Tables['accounts']['Row']): Account {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    type: row.type,
    currency: row.currency as Account['currency'],
    openingBalanceMinor: row.opening_balance_minor,
    isArchived: row.is_archived,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function mapTransaction(row: Tables['transactions']['Row']): Transaction {
  return {
    id: row.id,
    userId: row.user_id,
    kind: row.kind,
    status: row.status,
    amountMinor: row.amount_minor,
    occurredOn: row.occurred_on,
    accountId: row.account_id,
    transferAccountId: row.transfer_account_id,
    categoryId: row.category_id,
    payee: row.payee,
    notes: row.notes,
    recurringRuleId: row.recurring_rule_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function mapBudget(row: Tables['budgets']['Row']): Budget {
  return {
    id: row.id,
    userId: row.user_id,
    categoryId: row.category_id,
    month: row.month,
    amountMinor: row.amount_minor,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function mapRecurring(row: Tables['recurring_rules']['Row']): RecurringRule {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    kind: row.kind,
    amountMinor: row.amount_minor,
    accountId: row.account_id,
    transferAccountId: row.transfer_account_id,
    categoryId: row.category_id,
    payee: row.payee,
    notes: row.notes,
    frequency: row.frequency,
    intervalCount: row.interval_count,
    startDate: row.start_date,
    endDate: row.end_date,
    status: row.status,
    lastMaterializedOn: row.last_materialized_on,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function mapGoal(row: Tables['savings_goals']['Row']): SavingsGoal {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    targetAmountMinor: row.target_amount_minor,
    currentAmountMinor: row.current_amount_minor,
    targetDate: row.target_date,
    notes: row.notes,
    isArchived: row.is_archived,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function mapContribution(row: Tables['goal_contributions']['Row']): GoalContribution {
  return {
    id: row.id,
    userId: row.user_id,
    goalId: row.goal_id,
    amountMinor: row.amount_minor,
    contributedOn: row.contributed_on,
    notes: row.notes,
    createdAt: row.created_at,
  }
}

export function mapDebt(row: Tables['debts']['Row']): Debt {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    accountId: row.account_id,
    principalMinor: row.principal_minor,
    interestBps: row.interest_bps,
    minimumPaymentMinor: row.minimum_payment_minor,
    dueDay: row.due_day,
    notes: row.notes,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

/**
 * Supabase Database types for Fundsicles.
 * Structured for @supabase/supabase-js generic client typing.
 */

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

type AccountType =
  | 'cash'
  | 'checking'
  | 'savings'
  | 'e_wallet'
  | 'investment'
  | 'property'
  | 'credit_card'
  | 'loan'
  | 'asset'
  | 'liability'

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          display_name: string | null
          currency: string
          locale: string
          timezone: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          display_name?: string | null
          currency?: string
          locale?: string
          timezone?: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          display_name?: string | null
          currency?: string
          locale?: string
          timezone?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      categories: {
        Row: {
          id: string
          user_id: string
          name: string
          kind: 'income' | 'expense'
          color: string | null
          icon: string | null
          is_archived: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          name: string
          kind: 'income' | 'expense'
          color?: string | null
          icon?: string | null
          is_archived?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          name?: string
          kind?: 'income' | 'expense'
          color?: string | null
          icon?: string | null
          is_archived?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      accounts: {
        Row: {
          id: string
          user_id: string
          name: string
          type: AccountType
          currency: string
          opening_balance_minor: number
          is_archived: boolean
          notes: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          name: string
          type: AccountType
          currency?: string
          opening_balance_minor?: number
          is_archived?: boolean
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          name?: string
          type?: AccountType
          currency?: string
          opening_balance_minor?: number
          is_archived?: boolean
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      transactions: {
        Row: {
          id: string
          user_id: string
          kind: 'income' | 'expense' | 'transfer'
          status: 'pending' | 'posted'
          amount_minor: number
          occurred_on: string
          account_id: string
          transfer_account_id: string | null
          category_id: string | null
          payee: string | null
          notes: string | null
          recurring_rule_id: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          kind: 'income' | 'expense' | 'transfer'
          status?: 'pending' | 'posted'
          amount_minor: number
          occurred_on: string
          account_id: string
          transfer_account_id?: string | null
          category_id?: string | null
          payee?: string | null
          notes?: string | null
          recurring_rule_id?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          kind?: 'income' | 'expense' | 'transfer'
          status?: 'pending' | 'posted'
          amount_minor?: number
          occurred_on?: string
          account_id?: string
          transfer_account_id?: string | null
          category_id?: string | null
          payee?: string | null
          notes?: string | null
          recurring_rule_id?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      budgets: {
        Row: {
          id: string
          user_id: string
          category_id: string
          month: string
          amount_minor: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          category_id: string
          month: string
          amount_minor: number
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          category_id?: string
          month?: string
          amount_minor?: number
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      recurring_rules: {
        Row: {
          id: string
          user_id: string
          name: string
          kind: 'income' | 'expense' | 'transfer'
          amount_minor: number
          account_id: string
          transfer_account_id: string | null
          category_id: string | null
          payee: string | null
          notes: string | null
          frequency: 'daily' | 'weekly' | 'monthly' | 'yearly'
          interval_count: number
          start_date: string
          end_date: string | null
          status: 'active' | 'paused'
          last_materialized_on: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          name: string
          kind: 'income' | 'expense' | 'transfer'
          amount_minor: number
          account_id: string
          transfer_account_id?: string | null
          category_id?: string | null
          payee?: string | null
          notes?: string | null
          frequency: 'daily' | 'weekly' | 'monthly' | 'yearly'
          interval_count?: number
          start_date: string
          end_date?: string | null
          status?: 'active' | 'paused'
          last_materialized_on?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          name?: string
          kind?: 'income' | 'expense' | 'transfer'
          amount_minor?: number
          account_id?: string
          transfer_account_id?: string | null
          category_id?: string | null
          payee?: string | null
          notes?: string | null
          frequency?: 'daily' | 'weekly' | 'monthly' | 'yearly'
          interval_count?: number
          start_date?: string
          end_date?: string | null
          status?: 'active' | 'paused'
          last_materialized_on?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      savings_goals: {
        Row: {
          id: string
          user_id: string
          name: string
          target_amount_minor: number
          current_amount_minor: number
          target_date: string | null
          notes: string | null
          is_archived: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          name: string
          target_amount_minor: number
          current_amount_minor?: number
          target_date?: string | null
          notes?: string | null
          is_archived?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          name?: string
          target_amount_minor?: number
          current_amount_minor?: number
          target_date?: string | null
          notes?: string | null
          is_archived?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      goal_contributions: {
        Row: {
          id: string
          user_id: string
          goal_id: string
          amount_minor: number
          contributed_on: string
          notes: string | null
          created_at: string
        }
        Insert: {
          id?: string
          user_id: string
          goal_id: string
          amount_minor: number
          contributed_on: string
          notes?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          goal_id?: string
          amount_minor?: number
          contributed_on?: string
          notes?: string | null
          created_at?: string
        }
        Relationships: []
      }
      debts: {
        Row: {
          id: string
          user_id: string
          name: string
          account_id: string
          principal_minor: number
          interest_bps: number
          minimum_payment_minor: number
          due_day: number
          notes: string | null
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          name: string
          account_id: string
          principal_minor: number
          interest_bps?: number
          minimum_payment_minor: number
          due_day: number
          notes?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          name?: string
          account_id?: string
          principal_minor?: number
          interest_bps?: number
          minimum_payment_minor?: number
          due_day?: number
          notes?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      recurring_materializations: {
        Row: {
          id: string
          user_id: string
          recurring_rule_id: string
          occurred_on: string
          transaction_id: string
          created_at: string
        }
        Insert: {
          id?: string
          user_id: string
          recurring_rule_id: string
          occurred_on: string
          transaction_id: string
          created_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          recurring_rule_id?: string
          occurred_on?: string
          transaction_id?: string
          created_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      v_account_balances: {
        Row: {
          user_id: string | null
          account_id: string | null
          balance_minor: number | null
        }
        Relationships: []
      }
      v_monthly_cash_flow: {
        Row: {
          user_id: string | null
          month: string | null
          income_minor: number | null
          expense_minor: number | null
        }
        Relationships: []
      }
      v_category_spending: {
        Row: {
          user_id: string | null
          month: string | null
          category_id: string | null
          category_name: string | null
          amount_minor: number | null
        }
        Relationships: []
      }
      v_budget_actuals: {
        Row: {
          user_id: string | null
          budget_id: string | null
          category_id: string | null
          category_name: string | null
          month: string | null
          budget_minor: number | null
          spent_minor: number | null
        }
        Relationships: []
      }
      v_debt_balances: {
        Row: {
          user_id: string | null
          debt_id: string | null
          name: string | null
          balance_minor: number | null
          minimum_payment_minor: number | null
          due_day: number | null
        }
        Relationships: []
      }
      v_net_worth_history: {
        Row: {
          user_id: string | null
          as_of: string | null
          net_worth_minor: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      materialize_due_recurring_entries: {
        Args: { p_as_of?: string | null }
        Returns: number
      }
    }
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}

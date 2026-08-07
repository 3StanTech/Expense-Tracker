-- Fundsicles schema: tables, constraints, RLS, views, RPCs
-- Money is always integer minor units (centavos for PHP).

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- Updated-at helper
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := timezone('utc', now());
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  display_name text,
  currency text NOT NULL DEFAULT 'PHP' CHECK (currency = 'PHP'),
  locale text NOT NULL DEFAULT 'en-PH' CHECK (locale = 'en-PH'),
  timezone text NOT NULL DEFAULT 'Asia/Manila' CHECK (timezone = 'Asia/Manila'),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------
CREATE TABLE public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
  kind text NOT NULL CHECK (kind IN ('income', 'expense')),
  color text CHECK (color IS NULL OR color ~ '^#[0-9A-Fa-f]{6}$'),
  icon text,
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE UNIQUE INDEX categories_user_name_kind_ci
  ON public.categories (user_id, lower(name), kind);

CREATE INDEX categories_user_id_idx ON public.categories (user_id);

CREATE TRIGGER categories_set_updated_at
  BEFORE UPDATE ON public.categories
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Hardened signup trigger: empty search_path, schema-qualified objects
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, currency, locale, timezone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'display_name', split_part(NEW.email, '@', 1)),
    'PHP',
    'en-PH',
    'Asia/Manila'
  );

  INSERT INTO public.categories (user_id, name, kind, color) VALUES
    (NEW.id, 'Salary', 'income', '#059669'),
    (NEW.id, 'Freelance', 'income', '#0D9488'),
    (NEW.id, 'Other Income', 'income', '#14B8A6'),
    (NEW.id, 'Food & Dining', 'expense', '#DC2626'),
    (NEW.id, 'Transport', 'expense', '#EA580C'),
    (NEW.id, 'Bills & Utilities', 'expense', '#D97706'),
    (NEW.id, 'Shopping', 'expense', '#CA8A04'),
    (NEW.id, 'Health', 'expense', '#65A30D'),
    (NEW.id, 'Entertainment', 'expense', '#2563EB'),
    (NEW.id, 'Personal', 'expense', '#7C3AED'),
    (NEW.id, 'Other Expense', 'expense', '#6B7280');

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------
CREATE TABLE public.accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
  type text NOT NULL CHECK (type IN (
    'cash', 'checking', 'savings', 'e_wallet', 'investment', 'property',
    'credit_card', 'loan', 'asset', 'liability'
  )),
  currency text NOT NULL DEFAULT 'PHP' CHECK (currency = 'PHP'),
  opening_balance_minor bigint NOT NULL DEFAULT 0 CHECK (opening_balance_minor >= 0),
  is_archived boolean NOT NULL DEFAULT false,
  notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX accounts_user_id_idx ON public.accounts (user_id);
CREATE UNIQUE INDEX accounts_user_name_ci ON public.accounts (user_id, lower(name));

CREATE TRIGGER accounts_set_updated_at
  BEFORE UPDATE ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Transactions
-- ---------------------------------------------------------------------------
CREATE TABLE public.transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('income', 'expense', 'transfer')),
  status text NOT NULL DEFAULT 'posted' CHECK (status IN ('pending', 'posted')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  occurred_on date NOT NULL,
  account_id uuid NOT NULL REFERENCES public.accounts (id) ON DELETE RESTRICT,
  transfer_account_id uuid REFERENCES public.accounts (id) ON DELETE RESTRICT,
  category_id uuid REFERENCES public.categories (id) ON DELETE SET NULL,
  payee text CHECK (payee IS NULL OR char_length(payee) <= 120),
  notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
  recurring_rule_id uuid,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT transactions_transfer_accounts_differ CHECK (
    kind <> 'transfer'
    OR (
      transfer_account_id IS NOT NULL
      AND transfer_account_id <> account_id
      AND category_id IS NULL
    )
  ),
  CONSTRAINT transactions_non_transfer_no_dest CHECK (
    kind = 'transfer' OR transfer_account_id IS NULL
  )
);

CREATE INDEX transactions_user_id_idx ON public.transactions (user_id);
CREATE INDEX transactions_user_occurred_idx ON public.transactions (user_id, occurred_on DESC);
CREATE INDEX transactions_account_id_idx ON public.transactions (account_id);
CREATE INDEX transactions_category_id_idx ON public.transactions (category_id);
CREATE INDEX transactions_recurring_rule_id_idx ON public.transactions (recurring_rule_id);

CREATE TRIGGER transactions_set_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Ownership & category-kind validation
CREATE OR REPLACE FUNCTION public.validate_transaction_refs()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  acct_owner uuid;
  dest_owner uuid;
  cat_owner uuid;
  cat_kind text;
BEGIN
  SELECT a.user_id INTO acct_owner FROM public.accounts a WHERE a.id = NEW.account_id;
  IF acct_owner IS NULL OR acct_owner <> NEW.user_id THEN
    RAISE EXCEPTION 'account_id must belong to the same user';
  END IF;

  IF NEW.transfer_account_id IS NOT NULL THEN
    SELECT a.user_id INTO dest_owner FROM public.accounts a WHERE a.id = NEW.transfer_account_id;
    IF dest_owner IS NULL OR dest_owner <> NEW.user_id THEN
      RAISE EXCEPTION 'transfer_account_id must belong to the same user';
    END IF;
  END IF;

  IF NEW.category_id IS NOT NULL THEN
    SELECT c.user_id, c.kind INTO cat_owner, cat_kind
    FROM public.categories c WHERE c.id = NEW.category_id;
    IF cat_owner IS NULL OR cat_owner <> NEW.user_id THEN
      RAISE EXCEPTION 'category_id must belong to the same user';
    END IF;
    IF NEW.kind = 'income' AND cat_kind <> 'income' THEN
      RAISE EXCEPTION 'income transactions require an income category';
    END IF;
    IF NEW.kind = 'expense' AND cat_kind <> 'expense' THEN
      RAISE EXCEPTION 'expense transactions require an expense category';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER transactions_validate_refs
  BEFORE INSERT OR UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.validate_transaction_refs();

-- ---------------------------------------------------------------------------
-- Budgets
-- ---------------------------------------------------------------------------
CREATE TABLE public.budgets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES public.categories (id) ON DELETE CASCADE,
  month text NOT NULL CHECK (month ~ '^\d{4}-\d{2}$'),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (user_id, category_id, month)
);

CREATE INDEX budgets_user_month_idx ON public.budgets (user_id, month);

CREATE TRIGGER budgets_set_updated_at
  BEFORE UPDATE ON public.budgets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.validate_budget_refs()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  cat_owner uuid;
  cat_kind text;
BEGIN
  SELECT c.user_id, c.kind INTO cat_owner, cat_kind
  FROM public.categories c WHERE c.id = NEW.category_id;
  IF cat_owner IS NULL OR cat_owner <> NEW.user_id THEN
    RAISE EXCEPTION 'category_id must belong to the same user';
  END IF;
  IF cat_kind <> 'expense' THEN
    RAISE EXCEPTION 'budgets only apply to expense categories';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER budgets_validate_refs
  BEFORE INSERT OR UPDATE ON public.budgets
  FOR EACH ROW EXECUTE FUNCTION public.validate_budget_refs();

-- ---------------------------------------------------------------------------
-- Recurring rules
-- ---------------------------------------------------------------------------
CREATE TABLE public.recurring_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
  kind text NOT NULL CHECK (kind IN ('income', 'expense', 'transfer')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  account_id uuid NOT NULL REFERENCES public.accounts (id) ON DELETE RESTRICT,
  transfer_account_id uuid REFERENCES public.accounts (id) ON DELETE RESTRICT,
  category_id uuid REFERENCES public.categories (id) ON DELETE SET NULL,
  payee text CHECK (payee IS NULL OR char_length(payee) <= 120),
  notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
  frequency text NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
  interval_count integer NOT NULL DEFAULT 1 CHECK (interval_count BETWEEN 1 AND 365),
  start_date date NOT NULL,
  end_date date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused')),
  last_materialized_on date,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT recurring_end_after_start CHECK (end_date IS NULL OR end_date >= start_date),
  CONSTRAINT recurring_transfer_rules CHECK (
    kind <> 'transfer'
    OR (
      transfer_account_id IS NOT NULL
      AND transfer_account_id <> account_id
      AND category_id IS NULL
    )
  ),
  CONSTRAINT recurring_non_transfer_no_dest CHECK (
    kind = 'transfer' OR transfer_account_id IS NULL
  )
);

CREATE INDEX recurring_rules_user_id_idx ON public.recurring_rules (user_id);
CREATE INDEX recurring_rules_active_idx ON public.recurring_rules (user_id, status);

CREATE TRIGGER recurring_rules_set_updated_at
  BEFORE UPDATE ON public.recurring_rules
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_recurring_rule_fk
  FOREIGN KEY (recurring_rule_id) REFERENCES public.recurring_rules (id) ON DELETE SET NULL;

-- Idempotent materialization marker per rule+date
CREATE TABLE public.recurring_materializations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  recurring_rule_id uuid NOT NULL REFERENCES public.recurring_rules (id) ON DELETE CASCADE,
  occurred_on date NOT NULL,
  transaction_id uuid NOT NULL REFERENCES public.transactions (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (recurring_rule_id, occurred_on)
);

CREATE INDEX recurring_materializations_user_idx
  ON public.recurring_materializations (user_id);

-- ---------------------------------------------------------------------------
-- Savings goals (contributions do NOT change account balances)
-- ---------------------------------------------------------------------------
CREATE TABLE public.savings_goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
  target_amount_minor bigint NOT NULL CHECK (target_amount_minor > 0),
  current_amount_minor bigint NOT NULL DEFAULT 0 CHECK (current_amount_minor >= 0),
  target_date date,
  notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX savings_goals_user_id_idx ON public.savings_goals (user_id);

CREATE TRIGGER savings_goals_set_updated_at
  BEFORE UPDATE ON public.savings_goals
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.goal_contributions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  goal_id uuid NOT NULL REFERENCES public.savings_goals (id) ON DELETE CASCADE,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  contributed_on date NOT NULL,
  notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX goal_contributions_goal_id_idx ON public.goal_contributions (goal_id);
CREATE INDEX goal_contributions_user_id_idx ON public.goal_contributions (user_id);

CREATE OR REPLACE FUNCTION public.apply_goal_contribution()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  goal_owner uuid;
BEGIN
  SELECT g.user_id INTO goal_owner FROM public.savings_goals g WHERE g.id = NEW.goal_id;
  IF goal_owner IS NULL OR goal_owner <> NEW.user_id THEN
    RAISE EXCEPTION 'goal_id must belong to the same user';
  END IF;

  IF TG_OP = 'INSERT' THEN
    UPDATE public.savings_goals
    SET current_amount_minor = current_amount_minor + NEW.amount_minor
    WHERE id = NEW.goal_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.savings_goals
    SET current_amount_minor = GREATEST(0, current_amount_minor - OLD.amount_minor)
    WHERE id = OLD.goal_id;
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER goal_contributions_apply
  AFTER INSERT OR DELETE ON public.goal_contributions
  FOR EACH ROW EXECUTE FUNCTION public.apply_goal_contribution();

-- ---------------------------------------------------------------------------
-- Debts (linked to liability accounts; tracking only)
-- ---------------------------------------------------------------------------
CREATE TABLE public.debts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
  account_id uuid NOT NULL REFERENCES public.accounts (id) ON DELETE RESTRICT,
  principal_minor bigint NOT NULL CHECK (principal_minor > 0),
  interest_bps integer NOT NULL DEFAULT 0 CHECK (interest_bps >= 0 AND interest_bps <= 100000),
  minimum_payment_minor bigint NOT NULL CHECK (minimum_payment_minor > 0),
  due_day integer NOT NULL CHECK (due_day BETWEEN 1 AND 31),
  notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX debts_user_id_idx ON public.debts (user_id);

CREATE TRIGGER debts_set_updated_at
  BEFORE UPDATE ON public.debts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.validate_debt_refs()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  acct_owner uuid;
  acct_type text;
BEGIN
  SELECT a.user_id, a.type INTO acct_owner, acct_type
  FROM public.accounts a WHERE a.id = NEW.account_id;
  IF acct_owner IS NULL OR acct_owner <> NEW.user_id THEN
    RAISE EXCEPTION 'account_id must belong to the same user';
  END IF;
  IF acct_type NOT IN ('credit_card', 'loan', 'liability') THEN
    RAISE EXCEPTION 'debts must link to a liability account type';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER debts_validate_refs
  BEFORE INSERT OR UPDATE ON public.debts
  FOR EACH ROW EXECUTE FUNCTION public.validate_debt_refs();

-- ---------------------------------------------------------------------------
-- Recurring materialization helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_months_clamped(p_date date, p_months integer)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT (
    (date_trunc('month', p_date::timestamp) + (p_months || ' months')::interval)
    + LEAST(
      (EXTRACT(DAY FROM p_date)::integer - 1),
      (EXTRACT(DAY FROM (
        date_trunc('month', p_date::timestamp) + (p_months || ' months')::interval
        + '1 month'::interval - '1 day'::interval
      ))::integer - 1)
    ) * INTERVAL '1 day'
  )::date;
$$;

CREATE OR REPLACE FUNCTION public.next_recurrence_date(
  p_date date,
  p_frequency text,
  p_interval integer
)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF p_interval < 1 THEN
    RAISE EXCEPTION 'interval must be >= 1';
  END IF;
  CASE p_frequency
    WHEN 'daily' THEN RETURN p_date + p_interval;
    WHEN 'weekly' THEN RETURN p_date + (p_interval * 7);
    WHEN 'monthly' THEN RETURN public.add_months_clamped(p_date, p_interval);
    WHEN 'yearly' THEN RETURN public.add_months_clamped(p_date, p_interval * 12);
    ELSE RAISE EXCEPTION 'unknown frequency %', p_frequency;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.materialize_due_recurring_entries(p_as_of date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_as_of date := COALESCE(p_as_of, (timezone('Asia/Manila', now()))::date);
  r record;
  v_cursor date;
  v_created integer := 0;
  v_tx_id uuid;
  v_guard integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  FOR r IN
    SELECT *
    FROM public.recurring_rules rr
    WHERE rr.user_id = v_uid
      AND rr.status = 'active'
  LOOP
    v_cursor := r.start_date;
    v_guard := 0;

    -- Advance past last materialized
    IF r.last_materialized_on IS NOT NULL THEN
      WHILE v_cursor <= r.last_materialized_on AND v_guard < 10000 LOOP
        v_guard := v_guard + 1;
        EXIT WHEN r.end_date IS NOT NULL AND v_cursor > r.end_date;
        v_cursor := public.next_recurrence_date(v_cursor, r.frequency, r.interval_count);
      END LOOP;
    END IF;

    v_guard := 0;
    WHILE v_cursor <= v_as_of AND v_guard < 10000 LOOP
      v_guard := v_guard + 1;
      EXIT WHEN r.end_date IS NOT NULL AND v_cursor > r.end_date;

      -- Idempotent: skip if already materialized
      IF NOT EXISTS (
        SELECT 1 FROM public.recurring_materializations rm
        WHERE rm.recurring_rule_id = r.id AND rm.occurred_on = v_cursor
      ) THEN
        INSERT INTO public.transactions (
          user_id, kind, status, amount_minor, occurred_on,
          account_id, transfer_account_id, category_id, payee, notes, recurring_rule_id
        ) VALUES (
          r.user_id, r.kind, 'posted', r.amount_minor, v_cursor,
          r.account_id, r.transfer_account_id, r.category_id, r.payee, r.notes, r.id
        )
        RETURNING id INTO v_tx_id;

        INSERT INTO public.recurring_materializations (
          user_id, recurring_rule_id, occurred_on, transaction_id
        ) VALUES (r.user_id, r.id, v_cursor, v_tx_id);

        v_created := v_created + 1;
      END IF;

      UPDATE public.recurring_rules
      SET last_materialized_on = v_cursor
      WHERE id = r.id;

      v_cursor := public.next_recurrence_date(v_cursor, r.frequency, r.interval_count);
    END LOOP;
  END LOOP;

  RETURN v_created;
END;
$$;

REVOKE ALL ON FUNCTION public.materialize_due_recurring_entries(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.materialize_due_recurring_entries(date) TO authenticated;

-- ---------------------------------------------------------------------------
-- Derived views
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_account_balances
WITH (security_invoker = true)
AS
SELECT
  a.user_id,
  a.id AS account_id,
  CASE
    WHEN a.type IN ('credit_card', 'loan', 'liability') THEN
      a.opening_balance_minor
      - COALESCE(SUM(
          CASE
            WHEN t.status = 'posted' AND t.kind = 'income' AND t.account_id = a.id THEN t.amount_minor
            WHEN t.status = 'posted' AND t.kind = 'expense' AND t.account_id = a.id THEN -t.amount_minor
            WHEN t.status = 'posted' AND t.kind = 'transfer' AND t.account_id = a.id THEN -t.amount_minor
            WHEN t.status = 'posted' AND t.kind = 'transfer' AND t.transfer_account_id = a.id THEN t.amount_minor
            ELSE 0
          END
        ), 0)
    ELSE
      a.opening_balance_minor
      + COALESCE(SUM(
          CASE
            WHEN t.status = 'posted' AND t.kind = 'income' AND t.account_id = a.id THEN t.amount_minor
            WHEN t.status = 'posted' AND t.kind = 'expense' AND t.account_id = a.id THEN -t.amount_minor
            WHEN t.status = 'posted' AND t.kind = 'transfer' AND t.account_id = a.id THEN -t.amount_minor
            WHEN t.status = 'posted' AND t.kind = 'transfer' AND t.transfer_account_id = a.id THEN t.amount_minor
            ELSE 0
          END
        ), 0)
  END::bigint AS balance_minor
FROM public.accounts a
LEFT JOIN public.transactions t
  ON t.user_id = a.user_id
 AND (t.account_id = a.id OR t.transfer_account_id = a.id)
GROUP BY a.user_id, a.id, a.type, a.opening_balance_minor;

CREATE OR REPLACE VIEW public.v_monthly_cash_flow
WITH (security_invoker = true)
AS
SELECT
  t.user_id,
  to_char(t.occurred_on, 'YYYY-MM') AS month,
  COALESCE(SUM(CASE WHEN t.kind = 'income' THEN t.amount_minor ELSE 0 END), 0)::bigint AS income_minor,
  COALESCE(SUM(CASE WHEN t.kind = 'expense' THEN t.amount_minor ELSE 0 END), 0)::bigint AS expense_minor
FROM public.transactions t
WHERE t.status = 'posted'
  AND t.kind IN ('income', 'expense')
GROUP BY t.user_id, to_char(t.occurred_on, 'YYYY-MM');

CREATE OR REPLACE VIEW public.v_category_spending
WITH (security_invoker = true)
AS
SELECT
  t.user_id,
  to_char(t.occurred_on, 'YYYY-MM') AS month,
  t.category_id,
  c.name AS category_name,
  COALESCE(SUM(t.amount_minor), 0)::bigint AS amount_minor
FROM public.transactions t
JOIN public.categories c ON c.id = t.category_id
WHERE t.status = 'posted'
  AND t.kind = 'expense'
  AND t.category_id IS NOT NULL
GROUP BY t.user_id, to_char(t.occurred_on, 'YYYY-MM'), t.category_id, c.name;

CREATE OR REPLACE VIEW public.v_budget_actuals
WITH (security_invoker = true)
AS
SELECT
  b.user_id,
  b.id AS budget_id,
  b.category_id,
  c.name AS category_name,
  b.month,
  b.amount_minor AS budget_minor,
  COALESCE((
    SELECT SUM(t.amount_minor)::bigint
    FROM public.transactions t
    WHERE t.user_id = b.user_id
      AND t.category_id = b.category_id
      AND t.kind = 'expense'
      AND t.status = 'posted'
      AND to_char(t.occurred_on, 'YYYY-MM') = b.month
  ), 0)::bigint AS spent_minor
FROM public.budgets b
JOIN public.categories c ON c.id = b.category_id;

CREATE OR REPLACE VIEW public.v_debt_balances
WITH (security_invoker = true)
AS
SELECT
  d.user_id,
  d.id AS debt_id,
  d.name,
  COALESCE(ab.balance_minor, d.principal_minor)::bigint AS balance_minor,
  d.minimum_payment_minor,
  d.due_day
FROM public.debts d
LEFT JOIN public.v_account_balances ab ON ab.account_id = d.account_id AND ab.user_id = d.user_id
WHERE d.is_active = true;

-- Month-end net worth from opening balances + posted effects through each as_of date.
-- Does not reuse current v_account_balances for historical months.
-- Archived accounts are excluded; liability balances subtract from net worth.
CREATE OR REPLACE VIEW public.v_net_worth_history
WITH (security_invoker = true)
AS
WITH months AS (
  SELECT DISTINCT
    src.user_id,
    src.as_of
  FROM (
    SELECT
      t.user_id,
      (date_trunc('month', t.occurred_on::timestamp) + INTERVAL '1 month' - INTERVAL '1 day')::date AS as_of
    FROM public.transactions t
    WHERE t.status = 'posted'
    UNION
    SELECT
      a.user_id,
      (
        date_trunc('month', (a.created_at AT TIME ZONE 'UTC')::timestamp)
        + INTERVAL '1 month'
        - INTERVAL '1 day'
      )::date AS as_of
    FROM public.accounts a
  ) src
),
balances_as_of AS (
  SELECT
    m.user_id,
    m.as_of,
    a.type,
    CASE
      WHEN a.type IN ('credit_card', 'loan', 'liability') THEN
        a.opening_balance_minor
        - COALESCE(SUM(
            CASE
              WHEN t.id IS NULL THEN 0
              WHEN t.kind = 'income' AND t.account_id = a.id THEN t.amount_minor
              WHEN t.kind = 'expense' AND t.account_id = a.id THEN -t.amount_minor
              WHEN t.kind = 'transfer' AND t.account_id = a.id THEN -t.amount_minor
              WHEN t.kind = 'transfer' AND t.transfer_account_id = a.id THEN t.amount_minor
              ELSE 0
            END
          ), 0)
      ELSE
        a.opening_balance_minor
        + COALESCE(SUM(
            CASE
              WHEN t.id IS NULL THEN 0
              WHEN t.kind = 'income' AND t.account_id = a.id THEN t.amount_minor
              WHEN t.kind = 'expense' AND t.account_id = a.id THEN -t.amount_minor
              WHEN t.kind = 'transfer' AND t.account_id = a.id THEN -t.amount_minor
              WHEN t.kind = 'transfer' AND t.transfer_account_id = a.id THEN t.amount_minor
              ELSE 0
            END
          ), 0)
    END::bigint AS balance_minor
  FROM months m
  JOIN public.accounts a
    ON a.user_id = m.user_id
   AND a.is_archived = false
  LEFT JOIN public.transactions t
    ON t.user_id = a.user_id
   AND t.status = 'posted'
   AND t.occurred_on <= m.as_of
   AND (t.account_id = a.id OR t.transfer_account_id = a.id)
  GROUP BY m.user_id, m.as_of, a.id, a.type, a.opening_balance_minor
)
SELECT
  b.user_id,
  b.as_of::text AS as_of,
  COALESCE(SUM(
    CASE
      WHEN b.type IN ('credit_card', 'loan', 'liability') THEN -b.balance_minor
      ELSE b.balance_minor
    END
  ), 0)::bigint AS net_worth_minor
FROM balances_as_of b
GROUP BY b.user_id, b.as_of;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories FORCE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_rules FORCE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_materializations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_materializations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.savings_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.savings_goals FORCE ROW LEVEL SECURITY;
ALTER TABLE public.goal_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goal_contributions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.debts FORCE ROW LEVEL SECURITY;

-- Profiles
CREATE POLICY profiles_select_own ON public.profiles FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()));
CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));

-- Categories
CREATE POLICY categories_select_own ON public.categories FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY categories_insert_own ON public.categories FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY categories_update_own ON public.categories FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY categories_delete_own ON public.categories FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Accounts
CREATE POLICY accounts_select_own ON public.accounts FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY accounts_insert_own ON public.accounts FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY accounts_update_own ON public.accounts FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY accounts_delete_own ON public.accounts FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Transactions
CREATE POLICY transactions_select_own ON public.transactions FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY transactions_insert_own ON public.transactions FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY transactions_update_own ON public.transactions FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY transactions_delete_own ON public.transactions FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Budgets
CREATE POLICY budgets_select_own ON public.budgets FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY budgets_insert_own ON public.budgets FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY budgets_update_own ON public.budgets FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY budgets_delete_own ON public.budgets FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Recurring
CREATE POLICY recurring_select_own ON public.recurring_rules FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY recurring_insert_own ON public.recurring_rules FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY recurring_update_own ON public.recurring_rules FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY recurring_delete_own ON public.recurring_rules FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY recurring_mat_select_own ON public.recurring_materializations FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Goals
CREATE POLICY goals_select_own ON public.savings_goals FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY goals_insert_own ON public.savings_goals FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY goals_update_own ON public.savings_goals FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY goals_delete_own ON public.savings_goals FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY contributions_select_own ON public.goal_contributions FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY contributions_insert_own ON public.goal_contributions FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY contributions_delete_own ON public.goal_contributions FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Debts
CREATE POLICY debts_select_own ON public.debts FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY debts_insert_own ON public.debts FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY debts_update_own ON public.debts FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY debts_delete_own ON public.debts FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Grants: revoke anon, restrict authenticated
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.categories TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.accounts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.budgets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.recurring_rules TO authenticated;
GRANT SELECT ON public.recurring_materializations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.savings_goals TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.goal_contributions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.debts TO authenticated;
GRANT SELECT ON public.v_account_balances TO authenticated;
GRANT SELECT ON public.v_monthly_cash_flow TO authenticated;
GRANT SELECT ON public.v_category_spending TO authenticated;
GRANT SELECT ON public.v_budget_actuals TO authenticated;
GRANT SELECT ON public.v_debt_balances TO authenticated;
GRANT SELECT ON public.v_net_worth_history TO authenticated;

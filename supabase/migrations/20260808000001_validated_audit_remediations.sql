-- Validated audit remediations (security + functional schema).
-- Idempotent: safe after the init migration, and safe if re-applied.

-- ---------------------------------------------------------------------------
-- Accounts: archive-effective timestamp (set only at the database boundary)
-- ---------------------------------------------------------------------------
ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

COMMENT ON COLUMN public.accounts.archived_at IS
  'UTC timestamp when the account became archived. Set by trigger; not client-supplied. NULL means currently active.';

CREATE OR REPLACE FUNCTION public.sync_account_archived_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.is_archived THEN
    IF TG_OP = 'INSERT' OR OLD.is_archived IS DISTINCT FROM true THEN
      NEW.archived_at := timezone('utc', now());
    ELSIF OLD.archived_at IS NOT NULL THEN
      -- Stay archived: preserve the database-owned timestamp even if a client
      -- attempts to replace it directly.
      NEW.archived_at := OLD.archived_at;
    ELSE
      NEW.archived_at := timezone('utc', now());
    END IF;
  ELSE
    NEW.archived_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS accounts_sync_archived_at ON public.accounts;
CREATE TRIGGER accounts_sync_archived_at
  BEFORE INSERT OR UPDATE ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.sync_account_archived_at();

-- Backfill archived rows that predate the column.
UPDATE public.accounts
SET archived_at = COALESCE(updated_at, created_at, timezone('utc', now()))
WHERE is_archived = true AND archived_at IS NULL;

-- ---------------------------------------------------------------------------
-- Debts: principal_minor is historical/metadata only (not current balance)
-- ---------------------------------------------------------------------------
ALTER TABLE public.debts DROP CONSTRAINT IF EXISTS debts_principal_minor_check;
ALTER TABLE public.debts
  ADD CONSTRAINT debts_principal_minor_check CHECK (principal_minor >= 0);

COMMENT ON COLUMN public.debts.principal_minor IS
  'Historical original principal snapshot only. Current balance is always the linked liability account balance from v_account_balances; never use this column as a live-balance fallback.';

-- ---------------------------------------------------------------------------
-- Goal contribution DELETE: use OLD.*; preserve INSERT; cascade-safe
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_goal_contribution()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  goal_owner uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Direct deletes are already constrained by contribution RLS. During an
    -- ON DELETE CASCADE, the parent goal may no longer be visible, so update
    -- it only when it still exists instead of rejecting the cascade.
    UPDATE public.savings_goals
    SET current_amount_minor = GREATEST(0, current_amount_minor - OLD.amount_minor)
    WHERE id = OLD.goal_id
      AND user_id = OLD.user_id;
    RETURN OLD;
  END IF;

  SELECT g.user_id INTO goal_owner
  FROM public.savings_goals g
  WHERE g.id = NEW.goal_id;
  IF goal_owner IS NULL OR goal_owner <> NEW.user_id THEN
    RAISE EXCEPTION 'goal_id must belong to the same user';
  END IF;

  IF TG_OP = 'INSERT' THEN
    UPDATE public.savings_goals
    SET current_amount_minor = current_amount_minor + NEW.amount_minor
    WHERE id = NEW.goal_id;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Transaction refs: require recurring_rule_id ownership when set
-- ---------------------------------------------------------------------------
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
  rule_owner uuid;
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

  IF NEW.recurring_rule_id IS NOT NULL THEN
    SELECT rr.user_id INTO rule_owner
    FROM public.recurring_rules rr
    WHERE rr.id = NEW.recurring_rule_id;
    IF rule_owner IS NULL OR rule_owner <> NEW.user_id THEN
      RAISE EXCEPTION 'recurring_rule_id must belong to the same user';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Recurring rule refs + active-rule quota (cannot be bypassed via PostgREST)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_recurring_refs()
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
      RAISE EXCEPTION 'income recurring rules require an income category';
    END IF;
    IF NEW.kind = 'expense' AND cat_kind <> 'expense' THEN
      RAISE EXCEPTION 'expense recurring rules require an expense category';
    END IF;
    IF NEW.kind = 'transfer' THEN
      RAISE EXCEPTION 'transfer recurring rules cannot have a category';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS recurring_rules_validate_refs ON public.recurring_rules;
CREATE TRIGGER recurring_rules_validate_refs
  BEFORE INSERT OR UPDATE ON public.recurring_rules
  FOR EACH ROW EXECUTE FUNCTION public.validate_recurring_refs();

CREATE OR REPLACE FUNCTION public.enforce_active_recurring_quota()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_limit integer := 50;
  v_count integer;
BEGIN
  IF NEW.status = 'active' AND (
    TG_OP = 'INSERT'
    OR OLD.status IS DISTINCT FROM 'active'
  ) THEN
    -- Serialize quota checks per user within the transaction (concurrency-safe).
    PERFORM pg_advisory_xact_lock(hashtext('recurring-quota:' || NEW.user_id::text));

    SELECT count(*)::integer INTO v_count
    FROM public.recurring_rules rr
    WHERE rr.user_id = NEW.user_id
      AND rr.status = 'active'
      AND rr.id IS DISTINCT FROM NEW.id;

    IF v_count >= v_limit THEN
      RAISE EXCEPTION 'active recurring rule quota of % exceeded', v_limit;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS recurring_rules_enforce_quota ON public.recurring_rules;
CREATE TRIGGER recurring_rules_enforce_quota
  BEFORE INSERT OR UPDATE OF status ON public.recurring_rules
  FOR EACH ROW EXECUTE FUNCTION public.enforce_active_recurring_quota();

-- ---------------------------------------------------------------------------
-- Materialize: reject future Manila dates; invocation-wide write budget
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.materialize_due_recurring_entries(p_as_of date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_manila_today date := (timezone('Asia/Manila', now()))::date;
  v_as_of date := COALESCE(p_as_of, v_manila_today);
  r record;
  v_cursor date;
  v_created integer := 0;
  v_iterations integer := 0;
  v_tx_id uuid;
  v_write_budget integer := 200;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF v_as_of > v_manila_today THEN
    RAISE EXCEPTION 'p_as_of cannot be after the current Manila calendar date (%)', v_manila_today;
  END IF;

  FOR r IN
    SELECT *
    FROM public.recurring_rules rr
    WHERE rr.user_id = v_uid
      AND rr.status = 'active'
  LOOP
    IF r.last_materialized_on IS NOT NULL THEN
      v_cursor := public.next_recurrence_date(
        r.last_materialized_on,
        r.frequency,
        r.interval_count
      );
    ELSE
      v_cursor := r.start_date;
    END IF;

    WHILE v_cursor <= v_as_of LOOP
      EXIT WHEN r.end_date IS NOT NULL AND v_cursor > r.end_date;

      v_iterations := v_iterations + 1;
      IF v_iterations > v_write_budget THEN
        RAISE EXCEPTION
          'materialization work budget of % occurrences exceeded; reduce the backlog and retry',
          v_write_budget;
      END IF;

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
-- Debt balances: linked liability account balance is the sole current balance
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_debt_balances
WITH (security_invoker = true)
AS
SELECT
  d.user_id,
  d.id AS debt_id,
  d.name,
  ab.balance_minor::bigint AS balance_minor,
  d.minimum_payment_minor,
  d.due_day
FROM public.debts d
INNER JOIN public.v_account_balances ab
  ON ab.account_id = d.account_id
 AND ab.user_id = d.user_id
WHERE d.is_active = true;

GRANT SELECT ON public.v_debt_balances TO authenticated;

-- ---------------------------------------------------------------------------
-- Net worth history: creation boundary + preserve pre-archive months
-- ---------------------------------------------------------------------------
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
        date_trunc('month', (timezone('Asia/Manila', a.created_at))::timestamp)
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
   AND (timezone('Asia/Manila', a.created_at))::date <= m.as_of
   AND (
     a.archived_at IS NULL
     OR (timezone('Asia/Manila', a.archived_at))::date > m.as_of
   )
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

GRANT SELECT ON public.v_net_worth_history TO authenticated;

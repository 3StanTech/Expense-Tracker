-- Database isolation tests for Fundsicles.
-- Run against a local instance after migrations:
--   supabase db reset && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_and_isolation.sql
--
-- Rules:
--   * Forbidden operations FAIL the test if they succeed.
--   * Only expected, named database errors count as pass (no broad WHEN OTHERS swallow).
--   * Hosted Supabase credentials are never used here.

BEGIN;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_cond boolean, p_msg text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT COALESCE(p_cond, false) THEN
    RAISE EXCEPTION 'FAIL: %', p_msg;
  END IF;
  RAISE NOTICE 'PASS: %', p_msg;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_auth(p_uid uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.clear_auth()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- Seed users (superuser / migration owner context)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  user_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
BEGIN
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data
  )
  VALUES
    (
      user_a, 'authenticated', 'authenticated', 'a@example.com',
      crypt('password123', gen_salt('bf')), now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"User A"}'::jsonb
    ),
    (
      user_b, 'authenticated', 'authenticated', 'b@example.com',
      crypt('password123', gen_salt('bf')), now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"User B"}'::jsonb
    )
  ON CONFLICT (id) DO NOTHING;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.assert_true(
    EXISTS (SELECT 1 FROM public.profiles WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'profile created for user A on signup'
  );
  PERFORM pg_temp.assert_true(
    EXISTS (SELECT 1 FROM public.profiles WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    'profile created for user B on signup'
  );
END $$;

-- Seed as superuser (bypasses RLS) so fixture rows exist for isolation checks.
-- created_at is historical so net-worth month-ends before "now" still include openings.
INSERT INTO public.accounts (id, user_id, name, type, opening_balance_minor, is_archived, created_at)
VALUES
  ('a1111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Cash A', 'cash', 100000, false, '2023-12-01 00:00:00+00'),
  ('a2222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bank A', 'checking', 500000, false, '2023-12-01 00:00:00+00'),
  ('a3333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Card A', 'credit_card', 20000, false, '2023-12-01 00:00:00+00'),
  ('b1111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Cash B', 'cash', 200000, false, '2023-12-01 00:00:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.categories (id, user_id, name, kind)
VALUES
  ('c1111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Test Food', 'expense'),
  ('c2222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'B Food', 'expense')
ON CONFLICT DO NOTHING;

-- Historical net-worth fixtures: Jan expense, Feb income/transfer (different month-end NW)
INSERT INTO public.transactions (
  id, user_id, kind, status, amount_minor, occurred_on, account_id, transfer_account_id, category_id
) VALUES
  (
    'e1111111-1111-1111-1111-111111111111',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'expense', 'posted', 1500, '2024-01-15',
    'a1111111-1111-1111-1111-111111111111',
    NULL,
    'c1111111-1111-1111-1111-111111111111'
  ),
  (
    'e2222222-2222-2222-2222-222222222222',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'income', 'posted', 10000, '2024-02-10',
    'a1111111-1111-1111-1111-111111111111',
    NULL,
    NULL
  ),
  (
    'e3333333-3333-3333-3333-333333333333',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'transfer', 'posted', 2500, '2024-02-20',
    'a1111111-1111-1111-1111-111111111111',
    'a2222222-2222-2222-2222-222222222222',
    NULL
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.budgets (id, user_id, category_id, month, amount_minor)
VALUES (
  'b9011111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'c1111111-1111-1111-1111-111111111111',
  '2024-01',
  50000
)
ON CONFLICT DO NOTHING;

INSERT INTO public.recurring_rules (
  id, user_id, name, kind, amount_minor, account_id, category_id,
  frequency, interval_count, start_date, status
) VALUES (
  'f1111111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Monthly Rent',
  'expense',
  10000,
  'a1111111-1111-1111-1111-111111111111',
  'c1111111-1111-1111-1111-111111111111',
  'monthly',
  1,
  '2024-03-01',
  'active'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.savings_goals (id, user_id, name, target_amount_minor, current_amount_minor)
VALUES (
  '91111111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Emergency',
  1000000,
  0
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.goal_contributions (id, user_id, goal_id, amount_minor, contributed_on)
VALUES (
  '9c111111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '91111111-1111-1111-1111-111111111111',
  5000,
  '2024-02-01'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.debts (
  id, user_id, name, account_id, principal_minor, minimum_payment_minor, due_day
) VALUES (
  'd1111111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Card debt',
  'a3333333-3333-3333-3333-333333333333',
  20000,
  1000,
  15
)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Constraint / trigger assertions (expected errors only)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    INSERT INTO public.transactions (
      user_id, kind, status, amount_minor, occurred_on, account_id
    ) VALUES (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'expense', 'posted', 1000, CURRENT_DATE,
      'b1111111-1111-1111-1111-111111111111'
    );
    RAISE EXCEPTION 'FAIL: cross-user account reference was allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE;
      END IF;
      IF SQLERRM NOT ILIKE '%same user%' AND SQLERRM NOT ILIKE '%account_id%' THEN
        RAISE EXCEPTION 'FAIL: cross-user account rejected with unexpected error: %', SQLERRM;
      END IF;
      RAISE NOTICE 'PASS: cross-user account reference rejected';
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.transactions (
      user_id, kind, status, amount_minor, occurred_on, account_id, transfer_account_id
    ) VALUES (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'transfer', 'posted', 1000, CURRENT_DATE,
      'a1111111-1111-1111-1111-111111111111',
      'a1111111-1111-1111-1111-111111111111'
    );
    RAISE EXCEPTION 'FAIL: same-account transfer was allowed';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASS: same-account transfer rejected (check_violation)';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE;
      END IF;
      RAISE EXCEPTION 'FAIL: same-account transfer unexpected error: %', SQLERRM;
  END;
END $$;

-- Cash flow excludes transfers
DO $$
DECLARE
  exp bigint;
BEGIN
  SELECT expense_minor INTO exp
  FROM public.v_monthly_cash_flow
  WHERE user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    AND month = '2024-01';
  PERFORM pg_temp.assert_true(exp = 1500, format('cash flow expense Jan expected 1500 got %s', exp));
END $$;

-- Month clamp helpers
DO $$
BEGIN
  PERFORM pg_temp.assert_true(
    public.add_months_clamped('2024-01-31'::date, 1) = '2024-02-29'::date,
    'monthly clamp leap year'
  );
  PERFORM pg_temp.assert_true(
    public.add_months_clamped('2023-01-31'::date, 1) = '2023-02-28'::date,
    'monthly clamp non-leap'
  );
END $$;

-- Historical net worth: Jan and Feb must differ; archived opening excluded
DO $$
DECLARE
  nw_jan bigint;
  nw_feb bigint;
  expected_jan bigint;
  expected_feb bigint;
BEGIN
  -- Non-archived: Cash 100000, Bank 500000, Card liability 20000
  -- Jan as_of: cash 100000-1500=98500; bank 500000; card 20000 → NW = 98500+500000-20000 = 578500
  expected_jan := 578500;
  -- Feb: cash 98500+10000-2500=106000; bank 500000+2500=502500; card 20000 → NW = 106000+502500-20000 = 588500
  expected_feb := 588500;

  SELECT net_worth_minor INTO nw_jan
  FROM public.v_net_worth_history
  WHERE user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    AND as_of = '2024-01-31';

  SELECT net_worth_minor INTO nw_feb
  FROM public.v_net_worth_history
  WHERE user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    AND as_of = '2024-02-29';

  PERFORM pg_temp.assert_true(
    nw_jan = expected_jan,
    format('Jan net worth expected %s got %s', expected_jan, nw_jan)
  );
  PERFORM pg_temp.assert_true(
    nw_feb = expected_feb,
    format('Feb net worth expected %s got %s', expected_feb, nw_feb)
  );
  PERFORM pg_temp.assert_true(
    nw_jan IS DISTINCT FROM nw_feb,
    'historical months must not all reuse the same current balance total'
  );
END $$;

-- ---------------------------------------------------------------------------
-- Anonymous denial (grants revoked + no auth.uid)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count bigint;
BEGIN
  PERFORM pg_temp.clear_auth();
  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    BEGIN
      SELECT count(*) INTO v_count FROM public.accounts;
      RAISE EXCEPTION 'FAIL: anon SELECT on accounts succeeded (count=%)', v_count;
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: anon denied SELECT on accounts';
      WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL:%' THEN
          RAISE;
        END IF;
        RAISE EXCEPTION 'FAIL: anon SELECT unexpected error: %', SQLERRM;
    END;

    BEGIN
      INSERT INTO public.accounts (user_id, name, type, opening_balance_minor)
      VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Anon Hack', 'cash', 1);
      RAISE EXCEPTION 'FAIL: anon INSERT on accounts succeeded';
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: anon denied INSERT on accounts';
      WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL:%' THEN
          RAISE;
        END IF;
        RAISE EXCEPTION 'FAIL: anon INSERT unexpected error: %', SQLERRM;
    END;

    BEGIN
      SELECT count(*) INTO v_count FROM public.v_account_balances;
      RAISE EXCEPTION 'FAIL: anon SELECT on v_account_balances succeeded';
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: anon denied SELECT on v_account_balances';
      WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL:%' THEN
          RAISE;
        END IF;
        RAISE EXCEPTION 'FAIL: anon SELECT view unexpected error: %', SQLERRM;
    END;

    BEGIN
      PERFORM public.materialize_due_recurring_entries(CURRENT_DATE);
      RAISE EXCEPTION 'FAIL: anon execute materialize_due_recurring_entries succeeded';
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: anon denied execute materialize_due_recurring_entries';
      WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL:%' THEN
          RAISE;
        END IF;
        -- Function may be executable but raise not authenticated
        IF SQLERRM ILIKE '%not authenticated%' THEN
          RAISE NOTICE 'PASS: anon materialize rejected (not authenticated)';
        ELSE
          RAISE EXCEPTION 'FAIL: anon materialize unexpected error: %', SQLERRM;
        END IF;
    END;
  END;
  PERFORM pg_temp.clear_auth();
END $$;

-- ---------------------------------------------------------------------------
-- Authenticated isolation: user A vs user B
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count bigint;
  v_rows integer;
  v_name text;
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  user_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  id_a_acct uuid := 'a1111111-1111-1111-1111-111111111111';
  id_b_acct uuid := 'b1111111-1111-1111-1111-111111111111';
  id_a_cat uuid := 'c1111111-1111-1111-1111-111111111111';
  id_a_tx uuid := 'e1111111-1111-1111-1111-111111111111';
  id_a_budget uuid := 'b9011111-1111-1111-1111-111111111111';
  id_a_rule uuid := 'f1111111-1111-1111-1111-111111111111';
  id_a_goal uuid := '91111111-1111-1111-1111-111111111111';
  id_a_contrib uuid := '9c111111-1111-1111-1111-111111111111';
  id_a_debt uuid := 'd1111111-1111-1111-1111-111111111111';
BEGIN
  -- User A can SELECT own rows
  PERFORM pg_temp.set_auth(user_a);

  SELECT count(*) INTO v_count FROM public.accounts WHERE id = id_a_acct;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own accounts');

  SELECT count(*) INTO v_count FROM public.categories WHERE id = id_a_cat;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own categories');

  SELECT count(*) INTO v_count FROM public.transactions WHERE id = id_a_tx;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own transactions');

  SELECT count(*) INTO v_count FROM public.budgets WHERE id = id_a_budget;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own budgets');

  SELECT count(*) INTO v_count FROM public.recurring_rules WHERE id = id_a_rule;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own recurring_rules');

  SELECT count(*) INTO v_count FROM public.savings_goals WHERE id = id_a_goal;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own savings_goals');

  SELECT count(*) INTO v_count FROM public.goal_contributions WHERE id = id_a_contrib;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own goal_contributions');

  SELECT count(*) INTO v_count FROM public.debts WHERE id = id_a_debt;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own debts');

  SELECT count(*) INTO v_count FROM public.profiles WHERE id = user_a;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own profile');

  -- Derived views (own data only)
  SELECT count(*) INTO v_count FROM public.v_account_balances WHERE account_id = id_a_acct;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own v_account_balances');

  SELECT count(*) INTO v_count FROM public.v_monthly_cash_flow WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count >= 1, 'user A SELECT own v_monthly_cash_flow');

  SELECT count(*) INTO v_count FROM public.v_category_spending WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count >= 1, 'user A SELECT own v_category_spending');

  SELECT count(*) INTO v_count FROM public.v_budget_actuals WHERE budget_id = id_a_budget;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own v_budget_actuals');

  SELECT count(*) INTO v_count FROM public.v_debt_balances WHERE debt_id = id_a_debt;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A SELECT own v_debt_balances');

  SELECT count(*) INTO v_count FROM public.v_net_worth_history WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count >= 1, 'user A SELECT own v_net_worth_history');

  -- User A cannot see user B base rows
  SELECT count(*) INTO v_count FROM public.accounts WHERE id = id_b_acct;
  PERFORM pg_temp.assert_true(v_count = 0, 'user A cannot SELECT user B accounts');

  SELECT count(*) INTO v_count FROM public.categories WHERE user_id = user_b;
  PERFORM pg_temp.assert_true(v_count = 0, 'user A cannot SELECT user B categories');

  SELECT count(*) INTO v_count FROM public.profiles WHERE id = user_b;
  PERFORM pg_temp.assert_true(v_count = 0, 'user A cannot SELECT user B profile');

  SELECT count(*) INTO v_count FROM public.v_account_balances WHERE account_id = id_b_acct;
  PERFORM pg_temp.assert_true(v_count = 0, 'user A cannot SELECT user B v_account_balances');

  -- User A INSERT own account
  INSERT INTO public.accounts (id, user_id, name, type, opening_balance_minor)
  VALUES ('a5555555-5555-5555-5555-555555555555', user_a, 'Temp A', 'cash', 100);
  PERFORM pg_temp.assert_true(true, 'user A INSERT own account');

  -- User A INSERT as user B must fail (RLS WITH CHECK)
  BEGIN
    INSERT INTO public.accounts (user_id, name, type, opening_balance_minor)
    VALUES (user_b, 'Hijack B', 'cash', 1);
    RAISE EXCEPTION 'FAIL: user A INSERT with user_b user_id succeeded';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASS: user A INSERT foreign user_id denied (insufficient_privilege)';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE;
      END IF;
      IF SQLERRM ILIKE '%row-level security%' OR SQLERRM ILIKE '%policy%' THEN
        RAISE NOTICE 'PASS: user A INSERT foreign user_id denied (RLS)';
      ELSE
        RAISE EXCEPTION 'FAIL: user A foreign INSERT unexpected error: %', SQLERRM;
      END IF;
  END;

  -- User A UPDATE own row
  UPDATE public.accounts SET notes = 'owned' WHERE id = 'a5555555-5555-5555-5555-555555555555';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 1, 'user A UPDATE own account');

  -- User A UPDATE user B row must affect 0 rows
  UPDATE public.accounts SET name = 'Hacked' WHERE id = id_b_acct;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user A UPDATE user B account affects 0 rows');

  -- User A DELETE user B row must affect 0 rows
  DELETE FROM public.accounts WHERE id = id_b_acct;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user A DELETE user B account affects 0 rows');

  -- User A DELETE own temp account
  DELETE FROM public.accounts WHERE id = 'a5555555-5555-5555-5555-555555555555';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 1, 'user A DELETE own account');

  -- Switch to user B
  PERFORM pg_temp.set_auth(user_b);

  SELECT count(*) INTO v_count FROM public.accounts WHERE id = id_b_acct;
  PERFORM pg_temp.assert_true(v_count = 1, 'user B SELECT own accounts');

  SELECT count(*) INTO v_count FROM public.accounts WHERE id = id_a_acct;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A accounts');

  SELECT count(*) INTO v_count FROM public.transactions WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A transactions');

  SELECT count(*) INTO v_count FROM public.budgets WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A budgets');

  SELECT count(*) INTO v_count FROM public.recurring_rules WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A recurring_rules');

  SELECT count(*) INTO v_count FROM public.savings_goals WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A savings_goals');

  SELECT count(*) INTO v_count FROM public.goal_contributions WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A goal_contributions');

  SELECT count(*) INTO v_count FROM public.debts WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A debts');

  SELECT count(*) INTO v_count FROM public.v_net_worth_history WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A v_net_worth_history');

  SELECT count(*) INTO v_count FROM public.v_budget_actuals WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A v_budget_actuals');

  SELECT count(*) INTO v_count FROM public.v_debt_balances WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A v_debt_balances');

  SELECT count(*) INTO v_count FROM public.v_monthly_cash_flow WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A v_monthly_cash_flow');

  SELECT count(*) INTO v_count FROM public.v_category_spending WHERE user_id = user_a;
  PERFORM pg_temp.assert_true(v_count = 0, 'user B cannot SELECT user A v_category_spending');

  -- User B INSERT own, then fail foreign INSERT
  INSERT INTO public.accounts (id, user_id, name, type, opening_balance_minor)
  VALUES ('b2222222-2222-2222-2222-222222222222', user_b, 'Temp B', 'cash', 50);
  PERFORM pg_temp.assert_true(true, 'user B INSERT own account');

  BEGIN
    INSERT INTO public.transactions (
      user_id, kind, status, amount_minor, occurred_on, account_id
    ) VALUES (
      user_a, 'expense', 'posted', 100, CURRENT_DATE, id_a_acct
    );
    RAISE EXCEPTION 'FAIL: user B INSERT transaction for user A succeeded';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASS: user B INSERT foreign transaction denied (insufficient_privilege)';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE;
      END IF;
      IF SQLERRM = 'account_id must belong to the same user' THEN
        RAISE NOTICE 'PASS: user B INSERT foreign transaction denied (ownership guard)';
      ELSIF SQLERRM ILIKE '%row-level security%' OR SQLERRM ILIKE '%policy%' THEN
        RAISE NOTICE 'PASS: user B INSERT foreign transaction denied (RLS)';
      ELSE
        RAISE EXCEPTION 'FAIL: user B foreign tx INSERT unexpected error: %', SQLERRM;
      END IF;
  END;

  -- User B UPDATE/DELETE user A data must be no-ops under RLS
  UPDATE public.transactions SET notes = 'pwned' WHERE id = id_a_tx;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B UPDATE user A transaction affects 0 rows');

  DELETE FROM public.transactions WHERE id = id_a_tx;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B DELETE user A transaction affects 0 rows');

  UPDATE public.budgets SET amount_minor = 1 WHERE id = id_a_budget;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B UPDATE user A budget affects 0 rows');

  DELETE FROM public.budgets WHERE id = id_a_budget;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B DELETE user A budget affects 0 rows');

  UPDATE public.recurring_rules SET name = 'pwned' WHERE id = id_a_rule;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B UPDATE user A recurring_rules affects 0 rows');

  DELETE FROM public.recurring_rules WHERE id = id_a_rule;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B DELETE user A recurring_rules affects 0 rows');

  UPDATE public.savings_goals SET name = 'pwned' WHERE id = id_a_goal;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B UPDATE user A savings_goals affects 0 rows');

  DELETE FROM public.goal_contributions WHERE id = id_a_contrib;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B DELETE user A goal_contributions affects 0 rows');

  DELETE FROM public.savings_goals WHERE id = id_a_goal;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B DELETE user A savings_goals affects 0 rows');

  UPDATE public.debts SET name = 'pwned' WHERE id = id_a_debt;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B UPDATE user A debts affects 0 rows');

  DELETE FROM public.debts WHERE id = id_a_debt;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B DELETE user A debts affects 0 rows');

  UPDATE public.categories SET name = 'pwned' WHERE id = id_a_cat;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B UPDATE user A categories affects 0 rows');

  DELETE FROM public.categories WHERE id = id_a_cat;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B DELETE user A categories affects 0 rows');

  UPDATE public.profiles SET display_name = 'pwned' WHERE id = user_a;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user B UPDATE user A profile affects 0 rows');

  -- Confirm user A data still intact after B attacks (as B we cannot see it; switch back)
  PERFORM pg_temp.set_auth(user_a);
  SELECT name INTO v_name FROM public.accounts WHERE id = id_a_acct;
  PERFORM pg_temp.assert_true(v_name = 'Cash A', 'user A account name unchanged after B attacks');

  SELECT count(*) INTO v_count FROM public.transactions WHERE id = id_a_tx;
  PERFORM pg_temp.assert_true(v_count = 1, 'user A transaction still present after B delete attempt');

  DELETE FROM public.accounts WHERE id = 'b2222222-2222-2222-2222-222222222222';
  -- B owns that row; we are A — should not delete
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 0, 'user A cannot DELETE user B temp account');

  PERFORM pg_temp.set_auth(user_b);
  DELETE FROM public.accounts WHERE id = 'b2222222-2222-2222-2222-222222222222';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(v_rows = 1, 'user B DELETE own temp account');

  PERFORM pg_temp.clear_auth();
END $$;

-- ---------------------------------------------------------------------------
-- Recurring RPC idempotency (authenticated as user A)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  first_created integer;
  second_created integer;
  mat_count bigint;
  tx_count bigint;
BEGIN
  PERFORM pg_temp.set_auth(user_a);

  first_created := public.materialize_due_recurring_entries('2024-03-01'::date);
  PERFORM pg_temp.assert_true(
    first_created >= 1,
    format('first materialize creates entries (got %s)', first_created)
  );

  second_created := public.materialize_due_recurring_entries('2024-03-01'::date);
  PERFORM pg_temp.assert_true(
    second_created = 0,
    format('second materialize is idempotent (got %s)', second_created)
  );

  SELECT count(*) INTO mat_count
  FROM public.recurring_materializations
  WHERE recurring_rule_id = 'f1111111-1111-1111-1111-111111111111'
    AND occurred_on = '2024-03-01';
  PERFORM pg_temp.assert_true(mat_count = 1, 'exactly one materialization marker for rule+date');

  SELECT count(*) INTO tx_count
  FROM public.transactions
  WHERE recurring_rule_id = 'f1111111-1111-1111-1111-111111111111'
    AND occurred_on = '2024-03-01';
  PERFORM pg_temp.assert_true(tx_count = 1, 'exactly one transaction for rule+date');

  -- User B cannot materialize as if they owned A's rules (RPC scopes to auth.uid)
  PERFORM pg_temp.set_auth('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
  first_created := public.materialize_due_recurring_entries('2024-03-01'::date);
  PERFORM pg_temp.assert_true(
    first_created = 0,
    'user B materialize does not create entries for user A rules'
  );

  PERFORM pg_temp.clear_auth();
END $$;

-- ---------------------------------------------------------------------------
-- Materialize: reject future Manila dates; invocation-wide work budget
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_manila_today date := (timezone('Asia/Manila', now()))::date;
  v_future date := v_manila_today + 30;
BEGIN
  PERFORM pg_temp.set_auth(user_a);
  BEGIN
    PERFORM public.materialize_due_recurring_entries(v_future);
    RAISE EXCEPTION 'FAIL: future p_as_of was accepted';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE;
      END IF;
      IF SQLERRM ILIKE '%manila%' OR SQLERRM ILIKE '%p_as_of%' THEN
        RAISE NOTICE 'PASS: future p_as_of rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: future p_as_of unexpected error: %', SQLERRM;
      END IF;
  END;
  PERFORM pg_temp.clear_auth();
END $$;

DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_manila_today date := (timezone('Asia/Manila', now()))::date;
  v_start date := v_manila_today - 250;
BEGIN
  -- Superuser seed: daily rule that would create >200 due occurrences
  INSERT INTO public.recurring_rules (
    id, user_id, name, kind, amount_minor, account_id, category_id,
    frequency, interval_count, start_date, status
  ) VALUES (
    'f2222222-2222-2222-2222-222222222222',
    user_a,
    'Daily spam',
    'expense',
    100,
    'a1111111-1111-1111-1111-111111111111',
    'c1111111-1111-1111-1111-111111111111',
    'daily',
    1,
    v_start,
    'active'
  );

  PERFORM pg_temp.set_auth(user_a);
  BEGIN
    PERFORM public.materialize_due_recurring_entries(v_manila_today);
    RAISE EXCEPTION 'FAIL: materialization budget was not enforced';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE;
      END IF;
      IF SQLERRM ILIKE '%budget%' THEN
        RAISE NOTICE 'PASS: materialization work budget enforced';
      ELSE
        RAISE EXCEPTION 'FAIL: budget enforcement unexpected error: %', SQLERRM;
      END IF;
  END;

  -- Partial work must not remain after budget failure (statement aborted → rolled back in subxact)
  -- The EXCEPTION handler above creates a subtransaction; assert no rows for this rule.
  PERFORM pg_temp.assert_true(
    NOT EXISTS (
      SELECT 1 FROM public.recurring_materializations
      WHERE recurring_rule_id = 'f2222222-2222-2222-2222-222222222222'
    ),
    'budget failure leaves no partial materializations for daily spam rule'
  );

  PERFORM pg_temp.clear_auth();
  DELETE FROM public.recurring_rules WHERE id = 'f2222222-2222-2222-2222-222222222222';
END $$;

-- ---------------------------------------------------------------------------
-- Active recurring rule quota (50)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  i integer;
  v_count integer;
BEGIN
  -- Seed 49 additional active rules (seed already has 1: Monthly Rent, id f111...)
  -- After budget test cleanup, only the original fixture rule remains for user A.
  SELECT count(*)::integer INTO v_count
  FROM public.recurring_rules
  WHERE user_id = user_a AND status = 'active';

  FOR i IN 1..(50 - v_count) LOOP
    INSERT INTO public.recurring_rules (
      user_id, name, kind, amount_minor, account_id, category_id,
      frequency, interval_count, start_date, status
    ) VALUES (
      user_a,
      'Quota filler ' || i,
      'expense',
      100,
      'a1111111-1111-1111-1111-111111111111',
      'c1111111-1111-1111-1111-111111111111',
      'monthly',
      1,
      '2025-01-01',
      'active'
    );
  END LOOP;

  PERFORM pg_temp.set_auth(user_a);
  BEGIN
    INSERT INTO public.recurring_rules (
      user_id, name, kind, amount_minor, account_id, category_id,
      frequency, interval_count, start_date, status
    ) VALUES (
      user_a,
      'Quota overflow',
      'expense',
      100,
      'a1111111-1111-1111-1111-111111111111',
      'c1111111-1111-1111-1111-111111111111',
      'monthly',
      1,
      '2025-01-01',
      'active'
    );
    RAISE EXCEPTION 'FAIL: active recurring quota was not enforced';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE;
      END IF;
      IF SQLERRM ILIKE '%quota%' THEN
        RAISE NOTICE 'PASS: active recurring rule quota enforced';
      ELSE
        RAISE EXCEPTION 'FAIL: quota enforcement unexpected error: %', SQLERRM;
      END IF;
  END;
  PERFORM pg_temp.clear_auth();

  DELETE FROM public.recurring_rules
  WHERE user_id = user_a
    AND name LIKE 'Quota filler %';
END $$;

-- ---------------------------------------------------------------------------
-- Cross-tenant recurring_rules references (authenticated direct INSERT/UPDATE)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  user_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  id_b_acct uuid := 'b1111111-1111-1111-1111-111111111111';
  id_b_cat uuid := 'c2222222-2222-2222-2222-222222222222';
  id_a_rule uuid := 'f1111111-1111-1111-1111-111111111111';
BEGIN
  PERFORM pg_temp.set_auth(user_a);

  BEGIN
    INSERT INTO public.recurring_rules (
      user_id, name, kind, amount_minor, account_id, category_id,
      frequency, interval_count, start_date, status
    ) VALUES (
      user_a, 'Steal acct', 'expense', 100, id_b_acct, 'c1111111-1111-1111-1111-111111111111',
      'monthly', 1, '2025-01-01', 'active'
    );
    RAISE EXCEPTION 'FAIL: recurring cross-user account_id insert allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%account_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: recurring cross-user account_id insert rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring account_id insert unexpected: %', SQLERRM;
      END IF;
  END;

  BEGIN
    INSERT INTO public.recurring_rules (
      user_id, name, kind, amount_minor, account_id, category_id,
      frequency, interval_count, start_date, status
    ) VALUES (
      user_a, 'Steal cat', 'expense', 100,
      'a1111111-1111-1111-1111-111111111111', id_b_cat,
      'monthly', 1, '2025-01-01', 'active'
    );
    RAISE EXCEPTION 'FAIL: recurring cross-user category_id insert allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%category_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: recurring cross-user category_id insert rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring category_id insert unexpected: %', SQLERRM;
      END IF;
  END;

  BEGIN
    INSERT INTO public.recurring_rules (
      user_id, name, kind, amount_minor, account_id, transfer_account_id, category_id,
      frequency, interval_count, start_date, status
    ) VALUES (
      user_a, 'Steal transfer', 'transfer', 100,
      'a1111111-1111-1111-1111-111111111111', id_b_acct, NULL,
      'monthly', 1, '2025-01-01', 'active'
    );
    RAISE EXCEPTION 'FAIL: recurring cross-user transfer_account_id insert allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%transfer_account_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: recurring cross-user transfer_account_id insert rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring transfer_account_id insert unexpected: %', SQLERRM;
      END IF;
  END;

  BEGIN
    UPDATE public.recurring_rules
    SET account_id = id_b_acct
    WHERE id = id_a_rule;
    RAISE EXCEPTION 'FAIL: recurring cross-user account_id update allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%account_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: recurring cross-user account_id update rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring account_id update unexpected: %', SQLERRM;
      END IF;
  END;

  BEGIN
    UPDATE public.recurring_rules
    SET category_id = id_b_cat
    WHERE id = id_a_rule;
    RAISE EXCEPTION 'FAIL: recurring cross-user category_id update allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%category_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: recurring cross-user category_id update rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring category_id update unexpected: %', SQLERRM;
      END IF;
  END;

  -- transfer_account_id update: switch kind+dest atomically would need transfer shape;
  -- attempt setting transfer_account_id while expense (check constraint) or update transfer rule.
  INSERT INTO public.recurring_rules (
    id, user_id, name, kind, amount_minor, account_id, transfer_account_id, category_id,
    frequency, interval_count, start_date, status
  ) VALUES (
    'f3333333-3333-3333-3333-333333333333',
    user_a, 'Own transfer', 'transfer', 100,
    'a1111111-1111-1111-1111-111111111111',
    'a2222222-2222-2222-2222-222222222222',
    NULL,
    'monthly', 1, '2025-01-01', 'active'
  );

  BEGIN
    UPDATE public.recurring_rules
    SET transfer_account_id = id_b_acct
    WHERE id = 'f3333333-3333-3333-3333-333333333333';
    RAISE EXCEPTION 'FAIL: recurring cross-user transfer_account_id update allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%transfer_account_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: recurring cross-user transfer_account_id update rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring transfer_account_id update unexpected: %', SQLERRM;
      END IF;
  END;

  DELETE FROM public.recurring_rules WHERE id = 'f3333333-3333-3333-3333-333333333333';
  PERFORM pg_temp.clear_auth();
END $$;

-- ---------------------------------------------------------------------------
-- Cross-tenant transactions.recurring_rule_id
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  user_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  id_a_rule uuid := 'f1111111-1111-1111-1111-111111111111';
  id_tx uuid := 'e4444444-4444-4444-4444-444444444444';
BEGIN
  -- User B owns a rule
  INSERT INTO public.recurring_rules (
    id, user_id, name, kind, amount_minor, account_id, category_id,
    frequency, interval_count, start_date, status
  ) VALUES (
    'fbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    user_b, 'B rule', 'expense', 100,
    'b1111111-1111-1111-1111-111111111111',
    'c2222222-2222-2222-2222-222222222222',
    'monthly', 1, '2025-01-01', 'active'
  );

  PERFORM pg_temp.set_auth(user_a);
  BEGIN
    INSERT INTO public.transactions (
      user_id, kind, status, amount_minor, occurred_on, account_id, recurring_rule_id
    ) VALUES (
      user_a, 'expense', 'posted', 100, CURRENT_DATE,
      'a1111111-1111-1111-1111-111111111111',
      'fbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    );
    RAISE EXCEPTION 'FAIL: cross-user recurring_rule_id insert allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%recurring_rule_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: cross-user recurring_rule_id insert rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring_rule_id insert unexpected: %', SQLERRM;
      END IF;
  END;

  INSERT INTO public.transactions (
    id, user_id, kind, status, amount_minor, occurred_on, account_id, recurring_rule_id
  ) VALUES (
    id_tx, user_a, 'expense', 'posted', 100, CURRENT_DATE,
    'a1111111-1111-1111-1111-111111111111', id_a_rule
  );

  BEGIN
    UPDATE public.transactions
    SET recurring_rule_id = 'fbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    WHERE id = id_tx;
    RAISE EXCEPTION 'FAIL: cross-user recurring_rule_id update allowed';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      IF SQLERRM ILIKE '%recurring_rule_id%' OR SQLERRM ILIKE '%same user%' THEN
        RAISE NOTICE 'PASS: cross-user recurring_rule_id update rejected';
      ELSE
        RAISE EXCEPTION 'FAIL: recurring_rule_id update unexpected: %', SQLERRM;
      END IF;
  END;

  DELETE FROM public.transactions WHERE id = id_tx;
  PERFORM pg_temp.clear_auth();
  DELETE FROM public.recurring_rules WHERE id = 'fbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
END $$;

-- ---------------------------------------------------------------------------
-- Goal contribution DELETE + cascade ownership
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  goal_id uuid := '92222222-2222-2222-2222-222222222222';
  contrib_id uuid := '9c222222-2222-2222-2222-222222222222';
  v_current bigint;
BEGIN
  INSERT INTO public.savings_goals (id, user_id, name, target_amount_minor, current_amount_minor)
  VALUES (goal_id, user_a, 'Cascade goal', 100000, 0);

  INSERT INTO public.goal_contributions (id, user_id, goal_id, amount_minor, contributed_on)
  VALUES (contrib_id, user_a, goal_id, 2500, '2024-05-01');

  SELECT current_amount_minor INTO v_current FROM public.savings_goals WHERE id = goal_id;
  PERFORM pg_temp.assert_true(v_current = 2500, 'contribution INSERT increases goal total');

  PERFORM pg_temp.set_auth(user_a);
  DELETE FROM public.goal_contributions WHERE id = contrib_id;
  PERFORM pg_temp.clear_auth();

  SELECT current_amount_minor INTO v_current FROM public.savings_goals WHERE id = goal_id;
  PERFORM pg_temp.assert_true(v_current = 0, 'owner DELETE contribution subtracts exact amount');

  INSERT INTO public.goal_contributions (user_id, goal_id, amount_minor, contributed_on)
  VALUES (user_a, goal_id, 1000, '2024-05-02'),
         (user_a, goal_id, 2000, '2024-05-03');

  SELECT current_amount_minor INTO v_current FROM public.savings_goals WHERE id = goal_id;
  PERFORM pg_temp.assert_true(v_current = 3000, 'two contributions sum to 3000');

  PERFORM pg_temp.set_auth(user_a);
  DELETE FROM public.savings_goals WHERE id = goal_id;
  PERFORM pg_temp.clear_auth();

  PERFORM pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM public.savings_goals WHERE id = goal_id),
    'deleting goal cascades contributions without error'
  );
END $$;

-- ---------------------------------------------------------------------------
-- Debt balances: linked account only (zero balance explicit)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  debt_bal bigint;
  zero_debt uuid := 'd2222222-2222-2222-2222-222222222222';
  zero_acct uuid := 'a6666666-6666-6666-6666-666666666666';
BEGIN
  INSERT INTO public.accounts (id, user_id, name, type, opening_balance_minor, is_archived)
  VALUES (zero_acct, user_a, 'Paid off card', 'credit_card', 0, false);

  INSERT INTO public.debts (
    id, user_id, name, account_id, principal_minor, minimum_payment_minor, due_day
  ) VALUES (
    zero_debt, user_a, 'Zero bal debt', zero_acct, 50000, 1000, 1
  );

  SELECT balance_minor INTO debt_bal
  FROM public.v_debt_balances
  WHERE debt_id = zero_debt;

  PERFORM pg_temp.assert_true(
    debt_bal = 0,
    format('zero-balance liability debt shows account balance 0 (got %s), not principal_minor', debt_bal)
  );

  DELETE FROM public.debts WHERE id = zero_debt;
  DELETE FROM public.accounts WHERE id = zero_acct;
END $$;

-- ---------------------------------------------------------------------------
-- Net worth: creation boundary + archive preserves pre-archive history
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  user_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  late_acct uuid := 'a7777777-7777-7777-7777-777777777777';
  nw_jan bigint;
  nw_before_late bigint;
  nw_with_late bigint;
  nw_before_arch bigint;
  nw_after_arch bigint;
  arch_acct uuid := 'a8888888-8888-8888-8888-888888888888';
  archive_recorded_at timestamptz;
BEGIN
  -- Late-created account must not affect prior month-end history
  SELECT net_worth_minor INTO nw_before_late
  FROM public.v_net_worth_history
  WHERE user_id = user_a
  ORDER BY as_of DESC
  LIMIT 1;

  INSERT INTO public.accounts (
    id, user_id, name, type, opening_balance_minor, is_archived, created_at
  ) VALUES (
    late_acct, user_a, 'Late cash', 'cash', 999000, false, '2024-06-15 00:00:00+00'
  );

  SELECT net_worth_minor INTO nw_jan
  FROM public.v_net_worth_history
  WHERE user_id = user_a AND as_of = '2024-01-31';

  -- Jan expected remains 578500 (late account created in June must not apply)
  PERFORM pg_temp.assert_true(
    nw_jan = 578500,
    format('Jan NW ignores not-yet-created account (got %s)', nw_jan)
  );

  SELECT net_worth_minor INTO nw_with_late
  FROM public.v_net_worth_history
  WHERE user_id = user_a AND as_of = '2024-06-30';

  -- The late June cash account adds exactly its opening balance. Use the
  -- latest preceding value because earlier tests also materialize a recurring
  -- expense, which intentionally changes the later historical baseline.
  PERFORM pg_temp.assert_true(
    nw_with_late = nw_before_late + 999000,
    format('June NW includes late account opening (expected %s got %s)', nw_before_late + 999000, nw_with_late)
  );

  -- Archive: pre-archive months keep the account; post-archive months drop it
  INSERT INTO public.accounts (
    id, user_id, name, type, opening_balance_minor, is_archived, created_at
  ) VALUES (
    arch_acct, user_a, 'Archive me', 'cash', 111000, false, '2024-01-01 00:00:00+00'
  );

  SELECT net_worth_minor INTO nw_before_arch
  FROM public.v_net_worth_history
  WHERE user_id = user_a AND as_of = '2024-02-29';

  UPDATE public.accounts SET is_archived = true WHERE id = arch_acct;
  SELECT archived_at INTO archive_recorded_at
  FROM public.accounts WHERE id = arch_acct;
  UPDATE public.accounts
  SET archived_at = '2000-01-01 00:00:00+00'
  WHERE id = arch_acct;

  SELECT net_worth_minor INTO nw_after_arch
  FROM public.v_net_worth_history
  WHERE user_id = user_a AND as_of = '2024-02-29';

  PERFORM pg_temp.assert_true(
    nw_before_arch = nw_after_arch,
    format('Feb history preserved after archive (before %s after %s)', nw_before_arch, nw_after_arch)
  );

  -- A client cannot replace the database-owned archive timestamp directly.
  PERFORM pg_temp.assert_true(
    (SELECT archived_at FROM public.accounts WHERE id = arch_acct) = archive_recorded_at,
    'archive timestamp remains database-owned'
  );

  DELETE FROM public.accounts WHERE id IN (late_acct, arch_acct);
END $$;

ROLLBACK;

SELECT 'Database isolation tests completed (transaction rolled back)' AS result;

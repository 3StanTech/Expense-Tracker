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

-- Seed as superuser (bypasses RLS) so fixture rows exist for isolation checks
INSERT INTO public.accounts (id, user_id, name, type, opening_balance_minor, is_archived)
VALUES
  ('a1111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Cash A', 'cash', 100000, false),
  ('a2222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bank A', 'checking', 500000, false),
  ('a3333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Card A', 'credit_card', 20000, false),
  ('a4444444-4444-4444-4444-444444444444', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Archived A', 'cash', 9999, true),
  ('b1111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Cash B', 'cash', 200000, false)
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

ROLLBACK;

SELECT 'Database isolation tests completed (transaction rolled back)' AS result;

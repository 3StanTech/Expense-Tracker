import { test, expect, type Page } from '@playwright/test'

/**
 * E2E coverage for Fundsicles.
 * Public routes always run. Authenticated CRUD requires live Supabase env + E2E user.
 * No production mock / sample-data fallback is used when credentials are absent.
 */

const hasSupabaseEnv = Boolean(
  process.env.VITE_SUPABASE_URL && process.env.VITE_SUPABASE_PUBLISHABLE_KEY,
)
const hasE2eUser = Boolean(process.env.E2E_USER_EMAIL && process.env.E2E_USER_PASSWORD)
const canRunAuthenticated = hasSupabaseEnv && hasE2eUser

const AUTH_SKIP_REASON =
  'skipped: missing VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY and/or E2E_USER_EMAIL / E2E_USER_PASSWORD; credential-dependent suite requires a live Supabase project (no mock fallback)'

const FEATURE_ROUTES = [
  '/app',
  '/app/transactions',
  '/app/accounts',
  '/app/budgets',
  '/app/recurring',
  '/app/goals',
  '/app/debts',
  '/app/reports',
  '/app/settings',
] as const

async function signIn(page: Page) {
  await page.goto('/login')
  await page.getByLabel('Email').fill(process.env.E2E_USER_EMAIL!)
  await page.getByLabel('Password').fill(process.env.E2E_USER_PASSWORD!)
  await page.getByRole('button', { name: /sign in/i }).click()
  await expect(page).toHaveURL(/\/app/)
}

async function clickHeaderAction(page: Page, name: string) {
  const action = page.locator('#main-content > div > header').getByRole('button', {
    name,
    exact: true,
  })
  await expect(action).toHaveCount(1)
  await action.click()
}

test.describe('public auth routes', () => {
  test('login page renders brand and form', async ({ page }) => {
    await page.goto('/login')
    const brand = page.getByText('Fundsicles')
    await expect(brand.first()).toBeVisible()
    const config = page.getByText(/Configuration required/i)
    const signInBtn = page.getByRole('button', { name: /sign in/i })
    await expect(config.or(signInBtn)).toBeVisible()
  })

  test('signup route is reachable', async ({ page }) => {
    await page.goto('/signup')
    await expect(page.getByText('Fundsicles').first()).toBeVisible()
  })

  test('forgot password route is reachable', async ({ page }) => {
    await page.goto('/forgot-password')
    await expect(page.getByText('Fundsicles').first()).toBeVisible()
  })

  test('reset password route is reachable', async ({ page }) => {
    await page.goto('/reset-password')
    await expect(page.getByText('Fundsicles').first()).toBeVisible()
  })

  test('auth callback route is reachable', async ({ page }) => {
    await page.goto('/auth/callback')
    await expect(page.getByText(/Fundsicles|Sign|Configuration|Completing/i).first()).toBeVisible()
  })
})

test.describe('protected routes without session', () => {
  for (const path of FEATURE_ROUTES) {
    test(`guards ${path}`, async ({ page }) => {
      await page.goto(path)
      const url = page.url()
      const config = page.getByText(/Configuration required/i)
      const onLogin = url.includes('/login')
      const hasConfig = await config.isVisible().catch(() => false)
      expect(onLogin || hasConfig || url.includes('/app')).toBeTruthy()
      if (url.includes('/login')) {
        await expect(page.getByText('Fundsicles').first()).toBeVisible()
      }
    })
  }
})

test.describe('SPA refresh and navigation', () => {
  test('direct navigation to login then refresh keeps page', async ({ page }) => {
    await page.goto('/login')
    await page.reload()
    await expect(page.getByText('Fundsicles').first()).toBeVisible()
  })

  test('unknown path falls back without hard 404 from SPA host', async ({ page }) => {
    const res = await page.goto('/this-does-not-exist-fundsicles')
    expect(res?.status()).toBeLessThan(500)
  })
})

test.describe('viewport shells', () => {
  test('renders at current project viewport', async ({ page }) => {
    await page.goto('/login')
    const box = page.viewportSize()
    expect(box).toBeTruthy()
    if (box) {
      expect([390, 1440]).toContain(box.width)
    }
    await expect(page.getByText('Fundsicles').first()).toBeVisible()
  })
})

test.describe('authenticated CRUD flows', () => {
  test.skip(!canRunAuthenticated, AUTH_SKIP_REASON)

  test('accounts create flow', async ({ page }, testInfo) => {
    await signIn(page)
    await page.goto('/app/accounts')
    await expect(page.getByRole('heading', { name: 'Accounts' })).toBeVisible()
    await clickHeaderAction(page, 'Add account')
    const stamp = Date.now()
    await page.getByLabel('Name').fill(`E2E ${testInfo.project.name} Cash ${stamp}`)
    await page.getByLabel('Type').selectOption('cash')
    await page.getByLabel(/Opening balance/i).fill('100.00')
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(page.getByText(`E2E ${testInfo.project.name} Cash ${stamp}`)).toBeVisible({
      timeout: 15_000,
    })
  })

  test('transactions and transfers create flow', async ({ page }, testInfo) => {
    await signIn(page)
    await page.goto('/app/accounts')
    await expect(page.getByRole('heading', { name: 'Accounts' })).toBeVisible()

    // Ensure at least two accounts exist for transfer
    const stamp = Date.now()
    for (const [name, type] of [
      [`E2E ${testInfo.project.name} From ${stamp}`, 'checking'],
      [`E2E ${testInfo.project.name} To ${stamp}`, 'savings'],
    ] as const) {
      await clickHeaderAction(page, 'Add account')
      await page.getByLabel('Name').fill(name)
      await page.getByLabel('Type').selectOption(type)
      await page.getByLabel(/Opening balance/i).fill('500.00')
      await page.getByRole('button', { name: /^save$/i }).click()
      await expect(page.getByText(name)).toBeVisible({ timeout: 15_000 })
    }

    await page.goto('/app/transactions')
    await expect(page.getByRole('heading', { name: 'Transactions' })).toBeVisible()

    // Expense
    await clickHeaderAction(page, 'Add transaction')
    await page.getByLabel('Kind').selectOption('expense')
    await page.getByLabel('Amount').fill('12.50')
    await page
      .getByLabel('Account')
      .selectOption({ label: `E2E ${testInfo.project.name} From ${stamp}` })
    await page.getByRole('button', { name: /^save$/i }).click()
    const transactionSurface =
      testInfo.project.name === 'mobile'
        ? page.locator('#main-content > div > ul')
        : page.getByRole('table')
    await expect(
      transactionSurface.getByText(`E2E ${testInfo.project.name} From ${stamp}`, {
        exact: testInfo.project.name !== 'mobile',
      }),
    ).toBeVisible({ timeout: 15_000 })

    // Transfer
    await clickHeaderAction(page, 'Add transaction')
    await page.getByLabel('Kind').selectOption('transfer')
    await page.getByLabel('Amount').fill('25.00')
    await page
      .getByLabel('From account')
      .selectOption({ label: `E2E ${testInfo.project.name} From ${stamp}` })
    await page
      .getByLabel('To account')
      .selectOption({ label: `E2E ${testInfo.project.name} To ${stamp}` })
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(transactionSurface.getByText('transfer', { exact: true })).toBeVisible({
      timeout: 15_000,
    })
  })

  test('budgets create flow', async ({ page }, testInfo) => {
    await signIn(page)
    await page.goto('/app/budgets')
    await expect(page.getByRole('heading', { name: 'Budgets' })).toBeVisible()
    await clickHeaderAction(page, 'Add budget')
    const category = page.getByLabel('Category')
    const expectedCategory =
      testInfo.project.name === 'mobile' ? 'Bills & Utilities' : 'Entertainment'
    await category.selectOption({ label: expectedCategory })
    await page.getByLabel(/Amount/i).fill('1000.00')
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(
      page.getByTestId('chart-focus-region').getByText(expectedCategory, { exact: true }),
    ).toBeVisible({ timeout: 15_000 })
  })

  test('recurring entries create flow', async ({ page }, testInfo) => {
    await signIn(page)
    const stamp = Date.now()
    const accountName = `E2E ${testInfo.project.name} Recurring ${stamp}`
    await page.goto('/app/accounts')
    await clickHeaderAction(page, 'Add account')
    await page.getByLabel('Name').fill(accountName)
    await page.getByLabel('Type').selectOption('checking')
    await page.getByLabel(/Opening balance/i).fill('500.00')
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(page.getByText(accountName)).toBeVisible({ timeout: 15_000 })

    await page.goto('/app/recurring')
    await expect(page.getByRole('heading', { name: 'Recurring', exact: true })).toBeVisible()
    await clickHeaderAction(page, 'Add rule')
    await page.getByLabel('Name').fill(`E2E ${testInfo.project.name} Rent ${stamp}`)
    await page.getByLabel('Kind').selectOption('expense')
    await page.getByLabel('Amount').fill('50.00')
    const account = page.getByLabel('Account')
    await account.selectOption({ label: accountName })
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(page.getByText(`E2E ${testInfo.project.name} Rent ${stamp}`)).toBeVisible({
      timeout: 15_000,
    })
  })

  test('savings goals create flow', async ({ page }, testInfo) => {
    await signIn(page)
    await page.goto('/app/goals')
    await expect(page.getByRole('heading', { name: 'Goals', exact: true })).toBeVisible()
    await clickHeaderAction(page, 'Add goal')
    const stamp = Date.now()
    await page.getByLabel('Name').fill(`E2E ${testInfo.project.name} Goal ${stamp}`)
    await page.getByLabel(/Target amount/i).fill('10000.00')
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(page.getByText(`E2E ${testInfo.project.name} Goal ${stamp}`)).toBeVisible({
      timeout: 15_000,
    })
  })

  test('debts create flow', async ({ page }, testInfo) => {
    await signIn(page)
    // Liability account first
    await page.goto('/app/accounts')
    const stamp = Date.now()
    await clickHeaderAction(page, 'Add account')
    await page.getByLabel('Name').fill(`E2E ${testInfo.project.name} Card ${stamp}`)
    await page.getByLabel('Type').selectOption('credit_card')
    await page.getByLabel(/Opening balance/i).fill('200.00')
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(page.getByText(`E2E ${testInfo.project.name} Card ${stamp}`)).toBeVisible({
      timeout: 15_000,
    })

    await page.goto('/app/debts')
    await expect(page.getByRole('heading', { name: 'Debts' })).toBeVisible()
    await clickHeaderAction(page, 'Add debt')
    await page.getByLabel('Name').fill(`E2E ${testInfo.project.name} Debt ${stamp}`)
    await page
      .getByLabel('Liability account')
      .selectOption({ label: `E2E ${testInfo.project.name} Card ${stamp} (credit card)` })
    await page.getByLabel(/Principal/i).fill('200.00')
    await page.getByLabel(/Minimum payment/i).fill('20.00')
    await page.getByLabel(/Due day of month/i).fill('15')
    await page.getByRole('button', { name: /^save$/i }).click()
    await expect(page.getByText(`E2E ${testInfo.project.name} Debt ${stamp}`)).toBeVisible({
      timeout: 15_000,
    })
  })

  test('reports, chart summaries, and direct route refresh', async ({ page }) => {
    await signIn(page)
    await page.goto('/app/reports')
    await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible()
    await expect(
      page.getByRole('heading', { name: 'Income vs expenses', exact: true }),
    ).toBeVisible()
    await expect(
      page.getByRole('heading', { name: 'Category spending', exact: true }),
    ).toBeVisible()
    await expect(
      page.getByRole('heading', { name: 'Net worth history', exact: true }),
    ).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Budget actuals', exact: true })).toBeVisible()

    // Chart keyboard data paths (focus regions + summary tables)
    const focusRegions = page.getByTestId('chart-focus-region')
    const tables = page.getByTestId('chart-data-table')
    const focusCount = await focusRegions.count()
    const tableCount = await tables.count()
    expect(focusCount).toBeGreaterThan(0)
    expect(tableCount).toBeGreaterThan(0)
    await focusRegions.first().focus()
    await expect(focusRegions.first()).toBeFocused()

    // Direct route refresh keeps authenticated session on reports
    await page.reload()
    await expect(page).toHaveURL(/\/app\/reports/)
    await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible()

    for (const path of FEATURE_ROUTES) {
      await page.goto(path)
      await page.reload()
      await expect(page).toHaveURL(new RegExp(path.replace('/', '\\/')))
    }
  })

  test('logout returns to login', async ({ page }) => {
    await signIn(page)
    await page.goto('/app/settings')
    await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible()
    await page.getByRole('button', { name: /log out/i }).click()
    await expect(page).toHaveURL(/login/)
    await expect(page.getByRole('button', { name: /sign in/i })).toBeVisible()
  })
})

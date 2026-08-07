# Fundsicles

**Your money, made clear.**

Personal finance SPA for PHP (en-PH, Asia/Manila). Integer minor-unit money storage, Supabase auth + RLS, no bank sync or sample-data fallbacks.

## Stack

- Vite + React + TypeScript (strict)
- React Router, TanStack Query, Supabase JS
- React Hook Form + Zod, date-fns, Recharts, Tailwind CSS v4
- Vitest, Testing Library, Playwright

## Setup

```bash
cp .env.example .env
# Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY (public only)

npm ci
npm run dev
```

## Scripts

| Script                 | Purpose                                        |
| ---------------------- | ---------------------------------------------- |
| `npm run dev`          | Local dev server                               |
| `npm run build`        | Production build to `dist`                     |
| `npm run preview`      | Preview production build                       |
| `npm run typecheck`    | TypeScript project references                  |
| `npm run lint`         | Oxlint                                         |
| `npm run format:check` | Prettier check                                 |
| `npm test`             | Vitest unit/component tests                    |
| `npm run test:e2e`     | Playwright (mobile 390×844 + desktop 1440×900) |
| `npm run test:db`      | SQL isolation tests against local Supabase     |
| `npm run verify`       | typecheck + lint + format + unit tests + build |

## Database

Migrations live in `supabase/migrations/`. Apply with the Supabase CLI against the linked project:

```bash
supabase db push
# or
supabase db reset   # local only
```

DB tests: `supabase/tests/rls_and_isolation.sql` (start local Supabase, then run `npm run test:db`).

## Hosting

- **Vercel**: `vercel.json` — `npm ci && npm run build`, `dist`, SPA rewrites
- **Netlify**: `netlify.toml` + `public/_redirects` SPA fallback

Do not put service-role keys or database passwords in client env vars.

## Routes

| Public                                                                       | Protected                                                                                                                                   |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `/login`, `/signup`, `/forgot-password`, `/reset-password`, `/auth/callback` | `/app`, `/app/transactions`, `/app/accounts`, `/app/budgets`, `/app/recurring`, `/app/goals`, `/app/debts`, `/app/reports`, `/app/settings` |

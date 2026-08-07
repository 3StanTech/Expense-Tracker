import type { ReactNode } from 'react'
import { Button } from './Button'
import { BrandMark } from '@/components/brand/BrandMark'

export type EmptyIllustration = 'cash-flow' | 'goals'

const ILLUSTRATION_SRC: Record<EmptyIllustration, string> = {
  'cash-flow': '/illustrations/empty-cash-flow.webp',
  goals: '/illustrations/empty-goals.webp',
}

export function LoadingSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div className="space-y-3" aria-busy="true" aria-label="Loading">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="skeleton h-16 w-full" />
      ))}
    </div>
  )
}

export function EmptyState({
  title,
  description,
  action,
  illustration,
}: {
  title: string
  description: string
  action?: ReactNode
  /** Optional decorative art for sparse empty states. */
  illustration?: EmptyIllustration
}) {
  return (
    <div className="card flex flex-col items-start gap-3 p-6 text-left">
      {illustration ? (
        <img
          src={ILLUSTRATION_SRC[illustration]}
          alt=""
          width={160}
          height={160}
          className="h-28 w-28 object-contain sm:h-32 sm:w-32"
          decoding="async"
        />
      ) : null}
      <h3 className="font-display text-base font-semibold">{title}</h3>
      <p className="text-sm text-[var(--muted)]">{description}</p>
      {action}
    </div>
  )
}

export function ErrorState({
  title = 'Something went wrong',
  message,
  onRetry,
}: {
  title?: string
  message: string
  onRetry?: () => void
}) {
  return (
    <div className="card border-danger/30 p-6" role="alert">
      <h3 className="font-display text-base font-semibold text-danger">{title}</h3>
      <p className="mt-2 text-sm text-[var(--muted)]">{message}</p>
      {onRetry ? (
        <div className="mt-4">
          <Button variant="secondary" onClick={onRetry}>
            Try again
          </Button>
        </div>
      ) : null}
    </div>
  )
}

export function ConfigErrorState({ message, missing }: { message: string; missing: string[] }) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-lg flex-col justify-center gap-4 p-6">
      <div className="card p-6">
        <div className="flex items-center gap-2">
          <BrandMark size="sm" />
          <p className="font-display text-sm font-semibold uppercase tracking-wide text-primary-700">
            Fundsicles
          </p>
        </div>
        <h1 className="mt-2 font-display text-2xl font-semibold">Configuration required</h1>
        <p className="mt-3 text-[var(--muted)]">{message}</p>
        {missing.length > 0 ? (
          <ul className="mt-4 list-disc space-y-1 pl-5 text-sm">
            {missing.map((m) => (
              <li key={m}>
                <code>{m}</code>
              </li>
            ))}
          </ul>
        ) : null}
        <p className="mt-4 text-sm text-[var(--muted)]">
          Copy <code>.env.example</code> to <code>.env</code> and set your public Supabase values.
          Never add service-role keys.
        </p>
      </div>
    </main>
  )
}

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string
  description?: string
  actions?: ReactNode
}) {
  return (
    <header className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="font-display text-2xl font-semibold tracking-tight">{title}</h1>
        {description ? <p className="mt-1 text-sm text-[var(--muted)]">{description}</p> : null}
      </div>
      {actions}
    </header>
  )
}

export function MoneyText({
  minor,
  className = '',
  signed = false,
  negativeIndicator = false,
}: {
  minor: number
  className?: string
  signed?: boolean
  negativeIndicator?: boolean
}) {
  const negative = minor < 0
  const formatted = new Intl.NumberFormat('en-PH', {
    style: 'currency',
    currency: 'PHP',
    minimumFractionDigits: 2,
  }).format(Math.abs(minor) / 100)

  let display = formatted
  if (signed && minor > 0) display = `+${formatted}`
  if (minor < 0) display = `−${formatted}`

  return (
    <span className={className}>
      {negative && negativeIndicator ? (
        <span className="mr-1 inline-block" aria-hidden="true">
          ▼
        </span>
      ) : null}
      <span className="sr-only">
        {minor < 0 ? 'Negative ' : minor > 0 && signed ? 'Positive ' : ''}
      </span>
      {display}
    </span>
  )
}

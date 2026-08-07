import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { profileFormSchema } from '@/schemas/forms'
import { useAuth } from '@/features/auth/AuthProvider'
import { useProfile } from '@/features/data/hooks'
import { updateProfile } from '@/features/data/repositories'
import { PageHeader, LoadingSkeleton, ErrorState } from '@/components/ui/States'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { getErrorMessage } from '@/lib/errors'
import { useQueryClient } from '@tanstack/react-query'
import { queryKeys } from '@/lib/query-client'
import type { z } from 'zod'

const moreLinks = [
  { to: '/app/accounts', label: 'Accounts & categories' },
  { to: '/app/recurring', label: 'Recurring rules' },
  { to: '/app/debts', label: 'Debts' },
  { to: '/app/reports', label: 'Reports & export' },
]

export function SettingsPage() {
  const { user, signOut } = useAuth()
  const profile = useProfile()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  type ProfileInput = z.infer<typeof profileFormSchema>
  const form = useForm<ProfileInput>({
    resolver: zodResolver(profileFormSchema),
    values: {
      displayName: profile.data?.displayName ?? '',
    },
  })

  async function onSubmit(values: ProfileInput) {
    setError(null)
    setMessage(null)
    try {
      await updateProfile(values.displayName?.trim() || null)
      await qc.invalidateQueries({ queryKey: queryKeys.profile })
      setMessage('Profile saved.')
    } catch (e) {
      setError(getErrorMessage(e))
    }
  }

  async function handleLogout() {
    await signOut()
    navigate('/login', { replace: true })
  }

  if (profile.isLoading) {
    return (
      <div>
        <PageHeader title="Settings" />
        <LoadingSkeleton />
      </div>
    )
  }

  if (profile.error) {
    return (
      <ErrorState message={getErrorMessage(profile.error)} onRetry={() => void profile.refetch()} />
    )
  }

  return (
    <div>
      <PageHeader title="Settings" description="Profile, preferences, and sign out." />

      <nav className="mb-6 md:hidden" aria-label="More destinations">
        <ul className="card divide-y divide-[var(--line)]">
          {moreLinks.map((l) => (
            <li key={l.to}>
              <Link className="flex min-h-11 items-center px-4 py-3 text-sm font-medium" to={l.to}>
                {l.label}
              </Link>
            </li>
          ))}
        </ul>
      </nav>

      <section className="card p-4" aria-labelledby="profile-heading">
        <h2 id="profile-heading" className="mb-3 text-base font-semibold">
          Profile
        </h2>
        <p className="mb-3 text-sm text-[var(--muted)]">{user?.email}</p>
        <form className="max-w-md space-y-3" onSubmit={form.handleSubmit(onSubmit)}>
          <Input
            label="Display name"
            error={form.formState.errors.displayName?.message}
            {...form.register('displayName')}
          />
          <dl className="grid grid-cols-2 gap-2 text-sm">
            <div>
              <dt className="text-[var(--muted)]">Currency</dt>
              <dd className="font-medium">{profile.data?.currency ?? 'PHP'}</dd>
            </div>
            <div>
              <dt className="text-[var(--muted)]">Locale</dt>
              <dd className="font-medium">{profile.data?.locale ?? 'en-PH'}</dd>
            </div>
            <div className="col-span-2">
              <dt className="text-[var(--muted)]">Timezone</dt>
              <dd className="font-medium">{profile.data?.timezone ?? 'Asia/Manila'}</dd>
            </div>
          </dl>
          {message ? (
            <p className="text-sm text-primary-800" role="status">
              {message}
            </p>
          ) : null}
          {error ? (
            <p className="field-error" role="alert">
              {error}
            </p>
          ) : null}
          <Button type="submit" disabled={form.formState.isSubmitting}>
            Save profile
          </Button>
        </form>
      </section>

      <section className="card mt-4 p-4" aria-labelledby="session-heading">
        <h2 id="session-heading" className="mb-3 text-base font-semibold">
          Session
        </h2>
        <Button variant="danger" onClick={() => void handleLogout()}>
          Log out
        </Button>
      </section>

      <section className="card mt-4 p-4" aria-labelledby="about-heading">
        <h2 id="about-heading" className="mb-2 text-base font-semibold">
          About Fundsicles
        </h2>
        <p className="text-sm text-[var(--muted)]">
          Your money, made clear. Personal finance tracking with integer-centavo accuracy. No bank
          sync, no shared households, no sample data fallbacks.
        </p>
      </section>
    </div>
  )
}

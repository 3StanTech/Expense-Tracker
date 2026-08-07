import { useState } from 'react'
import { Link, Navigate, useNavigate, useLocation } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import {
  forgotPasswordSchema,
  loginSchema,
  resetPasswordSchema,
  signupSchema,
  type LoginInput,
  type SignupInput,
} from '@/schemas/forms'
import { useAuth } from './AuthProvider'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { getErrorMessage } from '@/lib/errors'
import { ConfigErrorState } from '@/components/ui/States'
import { getEnvStatus } from '@/lib/env'
import type { z } from 'zod'

function AuthLayout({
  title,
  subtitle,
  children,
}: {
  title: string
  subtitle: string
  children: React.ReactNode
}) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-center px-4 py-10">
      <div className="mb-8 text-center">
        <p className="text-sm font-semibold uppercase tracking-wide text-primary-700">Fundsicles</p>
        <h1 className="mt-2 text-2xl font-semibold">{title}</h1>
        <p className="mt-1 text-sm text-[var(--muted)]">{subtitle}</p>
      </div>
      <div className="card p-6">{children}</div>
    </main>
  )
}

export function LoginPage() {
  const { signIn, user, loading, configured, configMessage } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const from = (location.state as { from?: string } | null)?.from ?? '/app'
  const [serverError, setServerError] = useState<string | null>(null)

  const form = useForm<LoginInput>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  })

  if (!configured) {
    const status = getEnvStatus()
    return (
      <ConfigErrorState
        message={configMessage ?? 'Missing configuration'}
        missing={status.ok ? [] : status.missing}
      />
    )
  }

  if (!loading && user) return <Navigate to="/app" replace />

  async function onSubmit(values: LoginInput) {
    setServerError(null)
    try {
      await signIn(values.email, values.password)
      navigate(from, { replace: true })
    } catch (e) {
      setServerError(getErrorMessage(e, 'Sign in failed'))
    }
  }

  return (
    <AuthLayout title="Welcome back" subtitle="Your money, made clear.">
      <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)} noValidate>
        <Input
          label="Email"
          type="email"
          autoComplete="email"
          error={form.formState.errors.email?.message}
          {...form.register('email')}
        />
        <Input
          label="Password"
          type="password"
          autoComplete="current-password"
          error={form.formState.errors.password?.message}
          {...form.register('password')}
        />
        {serverError ? (
          <p className="field-error" role="alert">
            {serverError}
          </p>
        ) : null}
        <Button type="submit" fullWidth disabled={form.formState.isSubmitting}>
          {form.formState.isSubmitting ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>
      <div className="mt-4 flex flex-col gap-2 text-center text-sm">
        <Link className="text-primary-700 underline" to="/forgot-password">
          Forgot password?
        </Link>
        <p className="text-[var(--muted)]">
          No account?{' '}
          <Link className="text-primary-700 underline" to="/signup">
            Sign up
          </Link>
        </p>
      </div>
    </AuthLayout>
  )
}

export function SignupPage() {
  const { signUp, user, loading, configured, configMessage } = useAuth()
  const navigate = useNavigate()
  const [serverError, setServerError] = useState<string | null>(null)
  const [info, setInfo] = useState<string | null>(null)

  const form = useForm<SignupInput>({
    resolver: zodResolver(signupSchema),
    defaultValues: { email: '', password: '', confirmPassword: '', displayName: '' },
  })

  if (!configured) {
    const status = getEnvStatus()
    return (
      <ConfigErrorState
        message={configMessage ?? 'Missing configuration'}
        missing={status.ok ? [] : status.missing}
      />
    )
  }

  if (!loading && user) return <Navigate to="/app" replace />

  async function onSubmit(values: SignupInput) {
    setServerError(null)
    setInfo(null)
    try {
      const result = await signUp(values.email, values.password, values.displayName || undefined)
      if (result.needsConfirmation) {
        setInfo('Check your email to confirm your account, then sign in.')
      } else {
        navigate('/app', { replace: true })
      }
    } catch (e) {
      setServerError(getErrorMessage(e, 'Sign up failed'))
    }
  }

  return (
    <AuthLayout title="Create your account" subtitle="Track spending with clarity.">
      <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)} noValidate>
        <Input
          label="Display name"
          autoComplete="name"
          error={form.formState.errors.displayName?.message}
          {...form.register('displayName')}
        />
        <Input
          label="Email"
          type="email"
          autoComplete="email"
          error={form.formState.errors.email?.message}
          {...form.register('email')}
        />
        <Input
          label="Password"
          type="password"
          autoComplete="new-password"
          hint="At least 8 characters"
          error={form.formState.errors.password?.message}
          {...form.register('password')}
        />
        <Input
          label="Confirm password"
          type="password"
          autoComplete="new-password"
          error={form.formState.errors.confirmPassword?.message}
          {...form.register('confirmPassword')}
        />
        {serverError ? (
          <p className="field-error" role="alert">
            {serverError}
          </p>
        ) : null}
        {info ? (
          <p className="text-sm text-primary-800" role="status">
            {info}
          </p>
        ) : null}
        <Button type="submit" fullWidth disabled={form.formState.isSubmitting}>
          {form.formState.isSubmitting ? 'Creating…' : 'Sign up'}
        </Button>
      </form>
      <p className="mt-4 text-center text-sm text-[var(--muted)]">
        Already have an account?{' '}
        <Link className="text-primary-700 underline" to="/login">
          Sign in
        </Link>
      </p>
    </AuthLayout>
  )
}

export function ForgotPasswordPage() {
  const { resetPassword, configured, configMessage } = useAuth()
  const [serverError, setServerError] = useState<string | null>(null)
  const [info, setInfo] = useState<string | null>(null)
  type Forgot = z.infer<typeof forgotPasswordSchema>
  const form = useForm<Forgot>({
    resolver: zodResolver(forgotPasswordSchema),
    defaultValues: { email: '' },
  })

  if (!configured) {
    const status = getEnvStatus()
    return (
      <ConfigErrorState
        message={configMessage ?? 'Missing configuration'}
        missing={status.ok ? [] : status.missing}
      />
    )
  }

  async function onSubmit(values: Forgot) {
    setServerError(null)
    setInfo(null)
    try {
      await resetPassword(values.email)
      setInfo('If an account exists for that email, a reset link has been sent.')
    } catch (e) {
      setServerError(getErrorMessage(e))
    }
  }

  return (
    <AuthLayout title="Reset password" subtitle="We’ll email you a secure link.">
      <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)} noValidate>
        <Input
          label="Email"
          type="email"
          autoComplete="email"
          error={form.formState.errors.email?.message}
          {...form.register('email')}
        />
        {serverError ? (
          <p className="field-error" role="alert">
            {serverError}
          </p>
        ) : null}
        {info ? (
          <p className="text-sm text-primary-800" role="status">
            {info}
          </p>
        ) : null}
        <Button type="submit" fullWidth disabled={form.formState.isSubmitting}>
          Send reset link
        </Button>
      </form>
      <p className="mt-4 text-center text-sm">
        <Link className="text-primary-700 underline" to="/login">
          Back to sign in
        </Link>
      </p>
    </AuthLayout>
  )
}

export function ResetPasswordPage() {
  const { updatePassword, configured, configMessage } = useAuth()
  const navigate = useNavigate()
  const [serverError, setServerError] = useState<string | null>(null)
  type Reset = z.infer<typeof resetPasswordSchema>
  const form = useForm<Reset>({
    resolver: zodResolver(resetPasswordSchema),
    defaultValues: { password: '', confirmPassword: '' },
  })

  if (!configured) {
    const status = getEnvStatus()
    return (
      <ConfigErrorState
        message={configMessage ?? 'Missing configuration'}
        missing={status.ok ? [] : status.missing}
      />
    )
  }

  async function onSubmit(values: Reset) {
    setServerError(null)
    try {
      await updatePassword(values.password)
      navigate('/app', { replace: true })
    } catch (e) {
      setServerError(getErrorMessage(e))
    }
  }

  return (
    <AuthLayout title="Choose a new password" subtitle="Then continue to your dashboard.">
      <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)} noValidate>
        <Input
          label="New password"
          type="password"
          autoComplete="new-password"
          error={form.formState.errors.password?.message}
          {...form.register('password')}
        />
        <Input
          label="Confirm password"
          type="password"
          autoComplete="new-password"
          error={form.formState.errors.confirmPassword?.message}
          {...form.register('confirmPassword')}
        />
        {serverError ? (
          <p className="field-error" role="alert">
            {serverError}
          </p>
        ) : null}
        <Button type="submit" fullWidth disabled={form.formState.isSubmitting}>
          Update password
        </Button>
      </form>
    </AuthLayout>
  )
}

export function AuthCallbackPage() {
  const { user, loading, configured, configMessage } = useAuth()

  if (!configured) {
    const status = getEnvStatus()
    return (
      <ConfigErrorState
        message={configMessage ?? 'Missing configuration'}
        missing={status.ok ? [] : status.missing}
      />
    )
  }

  if (loading) {
    return (
      <main className="flex min-h-dvh items-center justify-center p-6">
        <p>Completing sign-in…</p>
      </main>
    )
  }

  if (user) return <Navigate to="/app" replace />
  return <Navigate to="/login" replace />
}

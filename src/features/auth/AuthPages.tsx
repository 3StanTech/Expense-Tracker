import { useRef, useState } from 'react'
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
import { Dialog } from '@/components/ui/Dialog'
import { getErrorMessage } from '@/lib/errors'
import { ConfigErrorState } from '@/components/ui/States'
import { BrandMark } from '@/components/brand/BrandMark'
import { getEnvStatus } from '@/lib/env'
import type { z } from 'zod'

const AUTH_TAGLINE = 'Your money, made clear.'

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
    <main className="min-h-dvh lg:grid lg:grid-cols-2">
      {/* Brand / hero panel — side on desktop, compact header on mobile */}
      <section
        className="auth-panel flex flex-col items-center justify-center px-6 py-8 lg:min-h-dvh lg:px-10 lg:py-12"
        aria-label="Brand"
      >
        <div className="flex w-full max-w-md flex-col items-center text-center lg:items-start lg:text-left">
          <div className="flex items-center gap-2.5">
            <BrandMark size="md" />
            <div>
              <p className="font-display text-lg font-semibold text-primary-700">Fundsicles</p>
              <p className="text-xs text-[var(--muted)] sm:text-sm">{AUTH_TAGLINE}</p>
            </div>
          </div>
          <img
            src="/illustrations/auth-hero.webp"
            alt="Friendly mint piggy bank with abstract coins and soft cash shapes"
            width={960}
            height={720}
            className="mt-6 w-full max-w-xs object-contain sm:max-w-sm lg:mt-10 lg:max-w-md"
            decoding="async"
          />
        </div>
      </section>

      {/* Form panel */}
      <section className="flex flex-col justify-center px-4 py-8 sm:px-8 lg:px-12 lg:py-12">
        <div className="mx-auto w-full max-w-md">
          <div className="mb-6 text-center lg:text-left">
            <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">
              {title}
            </h1>
            <p className="mt-1 text-sm text-[var(--muted)]">{subtitle}</p>
          </div>
          <div className="card p-6">{children}</div>
        </div>
      </section>
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
    <AuthLayout title="Make your money make sense" subtitle="Sign in to see the full picture.">
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
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [submittedEmail, setSubmittedEmail] = useState('')
  const emailInputRef = useRef<HTMLInputElement | null>(null)

  const form = useForm<SignupInput>({
    resolver: zodResolver(signupSchema),
    defaultValues: { email: '', password: '', confirmPassword: '', displayName: '' },
  })

  const { ref: emailRegisterRef, ...emailRegister } = form.register('email')

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
    try {
      const result = await signUp(values.email, values.password, values.displayName || undefined)
      if (result.needsConfirmation) {
        setSubmittedEmail(values.email)
        setConfirmOpen(true)
      } else {
        navigate('/app', { replace: true })
      }
    } catch (e) {
      setServerError(getErrorMessage(e, 'Sign up failed'))
    }
  }

  function handleUseAnotherEmail() {
    setConfirmOpen(false)
    // Preserve submitted email in the form field
    form.setValue('email', submittedEmail, { shouldDirty: true })
    // Restore focus after dialog unmount restores previous focus first
    requestAnimationFrame(() => {
      emailInputRef.current?.focus()
    })
  }

  function handleGoToSignIn() {
    setConfirmOpen(false)
    navigate('/login')
  }

  return (
    <AuthLayout title="Start your money story" subtitle={AUTH_TAGLINE}>
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
          {...emailRegister}
          ref={(el) => {
            emailRegisterRef(el)
            emailInputRef.current = el
          }}
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

      <Dialog
        open={confirmOpen}
        onClose={handleUseAnotherEmail}
        title="Check your inbox"
        footer={
          <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <Button type="button" variant="secondary" onClick={handleUseAnotherEmail}>
              Use another email
            </Button>
            <Button type="button" onClick={handleGoToSignIn}>
              Go to sign in
            </Button>
          </div>
        }
      >
        <p className="text-sm text-[var(--muted)]">
          We sent a message to{' '}
          <span className="font-semibold text-[var(--fg)]">{submittedEmail}</span>.
        </p>
        <p className="mt-3 text-sm text-[var(--muted)]">
          Click the verification link to activate your account. If you don’t see it, check your spam
          or junk folder.
        </p>
      </Dialog>
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
    <AuthLayout title="Let’s get you back in" subtitle="We’ll email you a secure link.">
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
    <AuthLayout title="Choose a fresh password" subtitle="Then continue to your dashboard.">
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

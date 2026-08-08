import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { ForgotPasswordPage, LoginPage, ResetPasswordPage, SignupPage } from './AuthPages'

const authMock = vi.hoisted(() => ({
  signIn: vi.fn(),
  signUp: vi.fn(),
  signOut: vi.fn(),
  resetPassword: vi.fn(),
  updatePassword: vi.fn(),
  user: null as null | { id: string; email?: string },
  loading: false,
  configured: true,
  configMessage: null as string | null,
  session: null,
}))

vi.mock('./AuthProvider', () => ({
  useAuth: () => ({
    signIn: authMock.signIn,
    signUp: authMock.signUp,
    signOut: authMock.signOut,
    resetPassword: authMock.resetPassword,
    updatePassword: authMock.updatePassword,
    user: authMock.user,
    loading: authMock.loading,
    configured: authMock.configured,
    configMessage: authMock.configMessage,
    session: authMock.session,
  }),
}))

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/signup" element={<SignupPage />} />
        <Route path="/forgot-password" element={<ForgotPasswordPage />} />
        <Route path="/reset-password" element={<ResetPasswordPage />} />
        <Route path="/app" element={<div>App home</div>} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('auth page copy', () => {
  beforeEach(() => {
    authMock.user = null
    authMock.loading = false
    authMock.configured = true
    authMock.configMessage = null
    authMock.signIn.mockReset()
    authMock.signUp.mockReset()
    authMock.resetPassword.mockReset()
    authMock.updatePassword.mockReset()
  })

  it('renders exact login heading and subtitle with brand tagline', () => {
    renderAt('/login')
    expect(screen.getByRole('heading', { name: 'Make your money make sense' })).toBeInTheDocument()
    expect(screen.getByText('Sign in to see the full picture.')).toBeInTheDocument()
    expect(screen.getAllByText('Your money, made clear.').length).toBeGreaterThan(0)
    expect(screen.getByText('Fundsicles')).toBeInTheDocument()
  })

  it('auth hero is full-bleed width on mobile and constrained on large screens', () => {
    renderAt('/login')
    const hero = screen.getByRole('img', {
      name: /open wallet with stylized bills and coins/i,
    })
    expect(hero.getAttribute('src')).toContain('auth-hero.png')
    // Mobile: edge-to-edge (no max-w-xs/sm cap); desktop: lg:max-w-md
    expect(hero.className).toContain('w-full')
    expect(hero.className).toContain('max-w-none')
    expect(hero.className).toContain('lg:max-w-md')
    expect(hero.className).not.toMatch(/max-w-xs/)
    // Brand section has no horizontal padding on mobile so image touches viewport edges
    const brand = screen.getByRole('region', { name: 'Brand' })
    expect(brand.className).not.toMatch(/(^|\s)px-6(\s|$)/)
    expect(brand.className).toContain('lg:px-10')
  })

  it('renders exact signup heading', () => {
    renderAt('/signup')
    expect(screen.getByRole('heading', { name: 'Start your money story' })).toBeInTheDocument()
  })

  it('renders exact forgot-password heading', () => {
    renderAt('/forgot-password')
    expect(screen.getByRole('heading', { name: 'Let’s get you back in' })).toBeInTheDocument()
  })

  it('renders exact reset-password heading', () => {
    renderAt('/reset-password')
    expect(screen.getByRole('heading', { name: 'Choose a fresh password' })).toBeInTheDocument()
  })
})

describe('signup confirmation modal', () => {
  beforeEach(() => {
    authMock.user = null
    authMock.loading = false
    authMock.configured = true
    authMock.signUp.mockReset()
  })

  async function fillValidSignup(
    user: ReturnType<typeof userEvent.setup>,
    email = 'you@example.com',
  ) {
    await user.type(screen.getByLabelText('Display name'), 'Alex')
    await user.type(screen.getByLabelText('Email'), email)
    await user.type(screen.getByLabelText('Password'), 'password1')
    await user.type(screen.getByLabelText('Confirm password'), 'password1')
  }

  it('opens Check your inbox modal with submitted email when confirmation is required', async () => {
    const user = userEvent.setup()
    authMock.signUp.mockResolvedValue({ needsConfirmation: true })
    renderAt('/signup')
    await fillValidSignup(user, 'confirm-me@example.com')
    await user.click(screen.getByRole('button', { name: 'Sign up' }))

    await waitFor(() => {
      expect(screen.getByRole('dialog', { name: 'Check your inbox' })).toBeInTheDocument()
    })
    expect(screen.getByText('confirm-me@example.com')).toBeInTheDocument()
    expect(
      screen.getByText(
        /Click the verification link to activate your account. If you don’t see it, check your spam or junk folder./,
      ),
    ).toBeInTheDocument()
  })

  it('Go to sign in navigates to /login', async () => {
    const user = userEvent.setup()
    authMock.signUp.mockResolvedValue({ needsConfirmation: true })
    renderAt('/signup')
    await fillValidSignup(user)
    await user.click(screen.getByRole('button', { name: 'Sign up' }))
    await waitFor(() => expect(screen.getByRole('dialog')).toBeInTheDocument())
    await user.click(screen.getByRole('button', { name: 'Go to sign in' }))
    await waitFor(() => {
      expect(
        screen.getByRole('heading', { name: 'Make your money make sense' }),
      ).toBeInTheDocument()
    })
  })

  it('Use another email closes modal, keeps email, and restores focus to email field', async () => {
    const user = userEvent.setup()
    authMock.signUp.mockResolvedValue({ needsConfirmation: true })
    renderAt('/signup')
    await fillValidSignup(user, 'keep@example.com')
    await user.click(screen.getByRole('button', { name: 'Sign up' }))
    await waitFor(() => expect(screen.getByRole('dialog')).toBeInTheDocument())
    await user.click(screen.getByRole('button', { name: 'Use another email' }))

    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })
    const email = screen.getByLabelText('Email') as HTMLInputElement
    expect(email.value).toBe('keep@example.com')
    await waitFor(() => {
      expect(email).toHaveFocus()
    })
  })

  it('navigates to /app immediately when signUp returns needsConfirmation=false', async () => {
    const user = userEvent.setup()
    authMock.signUp.mockResolvedValue({ needsConfirmation: false })
    renderAt('/signup')
    await fillValidSignup(user)
    await user.click(screen.getByRole('button', { name: 'Sign up' }))
    await waitFor(() => {
      expect(screen.getByText('App home')).toBeInTheDocument()
    })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('does not open modal on signup error', async () => {
    const user = userEvent.setup()
    authMock.signUp.mockRejectedValue(new Error('Email already registered'))
    renderAt('/signup')
    await fillValidSignup(user)
    await user.click(screen.getByRole('button', { name: 'Sign up' }))
    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent(/Email already registered/)
    })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { getEnvStatus } from '@/lib/env'
import { getSupabase } from '@/lib/supabase'
import { getErrorMessage } from '@/lib/errors'

interface AuthContextValue {
  session: Session | null
  user: User | null
  loading: boolean
  configured: boolean
  configMessage: string | null
  signIn: (email: string, password: string) => Promise<void>
  signUp: (
    email: string,
    password: string,
    displayName?: string,
  ) => Promise<{ needsConfirmation: boolean }>
  signOut: () => Promise<void>
  resetPassword: (email: string) => Promise<void>
  updatePassword: (password: string) => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const env = getEnvStatus()
  const configured = env.ok
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(configured)

  useEffect(() => {
    if (!configured) {
      setLoading(false)
      return
    }

    let mounted = true
    const supabase = getSupabase()

    supabase.auth.getSession().then(({ data, error }) => {
      if (!mounted) return
      if (error) {
        console.error(error)
        setSession(null)
      } else {
        setSession(data.session)
      }
      setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
      setLoading(false)
    })

    return () => {
      mounted = false
      sub.subscription.unsubscribe()
    }
  }, [configured])

  const signIn = useCallback(async (email: string, password: string) => {
    const { error } = await getSupabase().auth.signInWithPassword({ email, password })
    if (error) throw new Error(getErrorMessage(error, 'Could not sign in'))
  }, [])

  const signUp = useCallback(async (email: string, password: string, displayName?: string) => {
    const redirectTo = `${window.location.origin}/auth/callback`
    const { data, error } = await getSupabase().auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: redirectTo,
        data: displayName ? { display_name: displayName } : undefined,
      },
    })
    if (error) throw new Error(getErrorMessage(error, 'Could not sign up'))
    return { needsConfirmation: !data.session }
  }, [])

  const signOut = useCallback(async () => {
    const { error } = await getSupabase().auth.signOut()
    if (error) throw new Error(getErrorMessage(error, 'Could not sign out'))
  }, [])

  const resetPassword = useCallback(async (email: string) => {
    const redirectTo = `${window.location.origin}/reset-password`
    const { error } = await getSupabase().auth.resetPasswordForEmail(email, { redirectTo })
    if (error) throw new Error(getErrorMessage(error, 'Could not send reset email'))
  }, [])

  const updatePassword = useCallback(async (password: string) => {
    const { error } = await getSupabase().auth.updateUser({ password })
    if (error) throw new Error(getErrorMessage(error, 'Could not update password'))
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      user: session?.user ?? null,
      loading,
      configured,
      configMessage: env.ok ? null : env.message,
      signIn,
      signUp,
      signOut,
      resetPassword,
      updatePassword,
    }),
    [session, loading, configured, env, signIn, signUp, signOut, resetPassword, updatePassword],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}

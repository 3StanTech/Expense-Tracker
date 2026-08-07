import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { getEnvStatus } from './env'
import type { Database } from '@/types/database'

let client: SupabaseClient<Database> | null = null

export function getSupabase(): SupabaseClient<Database> {
  if (client) return client

  const status = getEnvStatus()
  if (!status.ok) {
    throw new Error(status.message)
  }

  client = createClient<Database>(
    status.env.VITE_SUPABASE_URL,
    status.env.VITE_SUPABASE_PUBLISHABLE_KEY,
    {
      auth: {
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: true,
      },
    },
  )
  return client
}

export function resetSupabaseClient(): void {
  client = null
}

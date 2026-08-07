import { z } from 'zod'

const envSchema = z.object({
  VITE_SUPABASE_URL: z.string().url('VITE_SUPABASE_URL must be a valid URL'),
  VITE_SUPABASE_PUBLISHABLE_KEY: z.string().min(1, 'VITE_SUPABASE_PUBLISHABLE_KEY is required'),
})

export type AppEnv = z.infer<typeof envSchema>

export type EnvStatus =
  | { ok: true; env: AppEnv }
  | { ok: false; missing: string[]; message: string }

function readRawEnv(): Record<string, string | undefined> {
  return {
    VITE_SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL,
    VITE_SUPABASE_PUBLISHABLE_KEY: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  }
}

export function getEnvStatus(): EnvStatus {
  const raw = readRawEnv()
  const missing: string[] = []

  if (!raw.VITE_SUPABASE_URL?.trim()) missing.push('VITE_SUPABASE_URL')
  if (!raw.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()) {
    missing.push('VITE_SUPABASE_PUBLISHABLE_KEY')
  }

  if (missing.length > 0) {
    return {
      ok: false,
      missing,
      message:
        'Supabase is not configured. Copy .env.example to .env and set the public client variables.',
    }
  }

  const parsed = envSchema.safeParse(raw)
  if (!parsed.success) {
    return {
      ok: false,
      missing: parsed.error.issues.map((i) => i.path.join('.')),
      message: parsed.error.issues.map((i) => i.message).join('; '),
    }
  }

  return { ok: true, env: parsed.data }
}

export function isEnvConfigured(): boolean {
  return getEnvStatus().ok
}

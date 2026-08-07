#!/usr/bin/env node
/**
 * Runs SQL database tests inside the local Supabase Postgres container.
 * Does not contact hosted Supabase.
 */
import { existsSync, readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const testFile = path.join(root, 'supabase/tests/rls_and_isolation.sql')
const migration = path.join(root, 'supabase/migrations/20260322000001_init_fundsicles.sql')
const configFile = path.join(root, 'supabase/config.toml')

if (!existsSync(testFile) || !existsSync(migration) || !existsSync(configFile)) {
  console.error('Missing Supabase config, migration, or test SQL files')
  process.exit(1)
}

const config = readFileSync(configFile, 'utf8')
const projectId = config.match(/^project_id\s*=\s*"([^"]+)"/m)?.[1]

if (!projectId) {
  console.error('Missing project_id in supabase/config.toml')
  process.exit(1)
}

const container = `supabase_db_${projectId}`
const sql = readFileSync(testFile, 'utf8')
const psql = spawnSync(
  'docker',
  [
    'exec',
    '-i',
    container,
    'psql',
    '-U',
    'postgres',
    '-d',
    'postgres',
    '-v',
    'ON_ERROR_STOP=1',
  ],
  { encoding: 'utf8', input: sql },
)

if (psql.error) {
  console.error('Failed to run Docker:', psql.error.message)
  process.exit(1)
}

if (psql.status !== 0 && psql.stderr?.includes('No such container')) {
  console.error(`Local Supabase is not running (${container}). Run: supabase start`)
  process.exit(1)
}

process.stdout.write(psql.stdout || '')
process.stderr.write(psql.stderr || '')
process.exit(psql.status ?? 1)

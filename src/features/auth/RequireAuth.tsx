import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from './AuthProvider'
import { LoadingSkeleton } from '@/components/ui/States'
import { ConfigErrorState } from '@/components/ui/States'
import { getEnvStatus } from '@/lib/env'

export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { user, loading, configured, configMessage } = useAuth()
  const location = useLocation()

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
      <div className="mx-auto max-w-md p-8">
        <LoadingSkeleton rows={4} />
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />
  }

  return children
}

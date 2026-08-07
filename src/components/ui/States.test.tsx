import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { EmptyState, MoneyText, ErrorState } from './States'

describe('EmptyState', () => {
  it('renders title and description', () => {
    render(<EmptyState title="Nothing here" description="Add something" />)
    expect(screen.getByText('Nothing here')).toBeInTheDocument()
    expect(screen.getByText('Add something')).toBeInTheDocument()
  })
})

describe('MoneyText', () => {
  it('shows negative indicator for negative amounts', () => {
    render(<MoneyText minor={-1500} negativeIndicator />)
    expect(screen.getByText(/Negative/)).toBeInTheDocument()
  })
})

function noopRetry() {
  return undefined
}

describe('ErrorState', () => {
  it('exposes retry control', () => {
    render(<ErrorState message="Network failed" onRetry={noopRetry} />)
    expect(screen.getByRole('button', { name: /try again/i })).toBeInTheDocument()
  })
})

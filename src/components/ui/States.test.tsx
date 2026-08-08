import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { EmptyState, MoneyText, ErrorState } from './States'

describe('EmptyState', () => {
  it('renders title and description', () => {
    render(<EmptyState title="Nothing here" description="Add something" />)
    expect(screen.getByText('Nothing here')).toBeInTheDocument()
    expect(screen.getByText('Add something')).toBeInTheDocument()
  })

  it('renders decorative illustration with empty alt when provided', () => {
    render(
      <EmptyState title="No cash flow yet" description="Post activity" illustration="cash-flow" />,
    )
    const decorative = document.querySelector('img[alt=""]') as HTMLImageElement | null
    expect(decorative).toBeTruthy()
    expect(decorative?.getAttribute('src')).toContain('empty-cash-flow.png')
    expect(decorative?.getAttribute('alt')).toBe('')
  })

  it('renders goals illustration source', () => {
    render(<EmptyState title="No goals" description="Add a goal" illustration="goals" />)
    const decorative = document.querySelector('img[alt=""]') as HTMLImageElement | null
    expect(decorative?.getAttribute('src')).toContain('empty-goals.png')
  })

  it('renders transactions illustration source', () => {
    render(<EmptyState title="No transactions" description="Add one" illustration="transactions" />)
    const decorative = document.querySelector('img[alt=""]') as HTMLImageElement | null
    expect(decorative?.getAttribute('src')).toContain('empty-transactions.png')
  })

  it('omits illustration when not provided', () => {
    render(<EmptyState title="Empty" description="Plain" />)
    expect(document.querySelector('img')).toBeNull()
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

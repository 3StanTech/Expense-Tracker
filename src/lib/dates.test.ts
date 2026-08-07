import { describe, expect, it } from 'vitest'
import { addMonthsClamped, generateOccurrences, nextOccurrence, monthKey } from './dates'

describe('addMonthsClamped', () => {
  it('clamps Jan 31 to Feb end in leap year', () => {
    const d = addMonthsClamped(new Date(2024, 0, 31), 1)
    expect(d.getFullYear()).toBe(2024)
    expect(d.getMonth()).toBe(1)
    expect(d.getDate()).toBe(29)
  })

  it('clamps Jan 31 to Feb 28 in non-leap year', () => {
    const d = addMonthsClamped(new Date(2023, 0, 31), 1)
    expect(d.getMonth()).toBe(1)
    expect(d.getDate()).toBe(28)
  })

  it('clamps Mar 31 + 1 month to Apr 30', () => {
    const d = addMonthsClamped(new Date(2024, 2, 31), 1)
    expect(d.getMonth()).toBe(3)
    expect(d.getDate()).toBe(30)
  })
})

describe('nextOccurrence', () => {
  it('advances by frequency', () => {
    const base = new Date(2024, 0, 15)
    expect(nextOccurrence(base, 'daily', 2).getDate()).toBe(17)
    expect(nextOccurrence(base, 'weekly', 1).getDate()).toBe(22)
    expect(nextOccurrence(base, 'monthly', 1).getMonth()).toBe(1)
    expect(nextOccurrence(base, 'yearly', 1).getFullYear()).toBe(2025)
  })
})

describe('generateOccurrences', () => {
  it('is idempotent relative to lastMaterialized', () => {
    const first = generateOccurrences({
      startDate: '2024-01-01',
      endDate: null,
      frequency: 'monthly',
      interval: 1,
      asOf: '2024-03-15',
      lastMaterialized: null,
    })
    expect(first).toEqual(['2024-01-01', '2024-02-01', '2024-03-01'])

    const second = generateOccurrences({
      startDate: '2024-01-01',
      endDate: null,
      frequency: 'monthly',
      interval: 1,
      asOf: '2024-03-15',
      lastMaterialized: '2024-03-01',
    })
    expect(second).toEqual([])
  })
})

describe('monthKey', () => {
  it('formats yyyy-MM', () => {
    expect(monthKey('2024-06-15')).toBe('2024-06')
  })
})

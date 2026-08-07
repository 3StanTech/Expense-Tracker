type BrandMarkSize = 'sm' | 'md' | 'lg'

const sizeMap: Record<BrandMarkSize, string> = {
  sm: 'h-6 w-6',
  md: 'h-8 w-8',
  lg: 'h-10 w-10',
}

/**
 * Code-built mark informed by the generated piggy/coin icon concept:
 * mint tile, gold coin slot, coin accent, coral cheek — legible at 16px.
 */
export function BrandMark({
  size = 'md',
  className = '',
  title,
}: {
  size?: BrandMarkSize
  className?: string
  /** When set, mark is meaningful; otherwise decorative. */
  title?: string
}) {
  const decorative = !title
  return (
    <svg
      className={`${sizeMap[size]} shrink-0 ${className}`.trim()}
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      role={decorative ? 'img' : 'img'}
      aria-hidden={decorative ? true : undefined}
      aria-label={title}
    >
      {title ? <title>{title}</title> : null}
      <rect width="32" height="32" rx="8" fill="#5EEAD4" />
      <rect x="9" y="8" width="14" height="5" rx="2.5" fill="#FBBF24" />
      <rect x="11" y="9.5" width="10" height="2" rx="1" fill="#1C1917" />
      <circle cx="22.5" cy="21.5" r="5.5" fill="#F59E0B" />
      <circle cx="22.5" cy="21.5" r="3.5" fill="#FBBF24" />
      <circle cx="11" cy="20" r="2" fill="#FB7185" />
      <circle cx="13.5" cy="17" r="1.35" fill="#1C1917" />
      <circle cx="18" cy="17" r="1.35" fill="#1C1917" />
      <path
        d="M13.2 19.6c1.2 1.5 3.4 1.5 4.6 0"
        stroke="#1C1917"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
    </svg>
  )
}

import { z } from 'zod'
import {
  accountTypeSchema,
  categoryKindSchema,
  emailSchema,
  frequencySchema,
  isoDateSchema,
  monthSchema,
  nameSchema,
  nonNegativeMoneyStringSchema,
  notesSchema,
  passwordSchema,
  payeeSchema,
  positiveMoneyStringSchema,
  recurrenceStatusSchema,
  transactionKindSchema,
  transactionStatusSchema,
  uuidSchema,
} from './common'

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1, 'Password is required'),
})

export const signupSchema = z
  .object({
    email: emailSchema,
    password: passwordSchema,
    confirmPassword: z.string().min(1, 'Confirm your password'),
    displayName: z.string().trim().max(80).optional().or(z.literal('')),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  })

export const forgotPasswordSchema = z.object({
  email: emailSchema,
})

export const resetPasswordSchema = z
  .object({
    password: passwordSchema,
    confirmPassword: z.string().min(1, 'Confirm your password'),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  })

export const categoryFormSchema = z.object({
  name: nameSchema,
  kind: categoryKindSchema,
  color: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/, 'Color must be a hex value')
    .optional()
    .or(z.literal(''))
    .transform((v) => (v ? v : null)),
})

export const accountFormSchema = z.object({
  name: nameSchema,
  type: accountTypeSchema,
  openingBalance: nonNegativeMoneyStringSchema,
  notes: notesSchema,
})

const optionalUuid = z
  .union([uuidSchema, z.literal(''), z.null(), z.undefined()])
  .transform((v) => (v ? v : null))

export const transactionFormSchema = z
  .object({
    kind: transactionKindSchema,
    status: transactionStatusSchema.default('posted'),
    amount: positiveMoneyStringSchema,
    occurredOn: isoDateSchema,
    accountId: uuidSchema,
    transferAccountId: optionalUuid,
    categoryId: optionalUuid,
    payee: payeeSchema,
    notes: notesSchema,
  })
  .superRefine((data, ctx) => {
    if (data.kind === 'transfer') {
      if (!data.transferAccountId) {
        ctx.addIssue({
          code: 'custom',
          message: 'Destination account is required for transfers',
          path: ['transferAccountId'],
        })
      } else if (data.transferAccountId === data.accountId) {
        ctx.addIssue({
          code: 'custom',
          message: 'Source and destination accounts must differ',
          path: ['transferAccountId'],
        })
      }
      if (data.categoryId) {
        ctx.addIssue({
          code: 'custom',
          message: 'Transfers cannot have a category',
          path: ['categoryId'],
        })
      }
    } else {
      if (data.transferAccountId) {
        ctx.addIssue({
          code: 'custom',
          message: 'Only transfers may set a destination account',
          path: ['transferAccountId'],
        })
      }
    }
  })

export const budgetFormSchema = z.object({
  categoryId: uuidSchema,
  month: monthSchema,
  amount: positiveMoneyStringSchema,
})

export const recurringFormSchema = z
  .object({
    name: nameSchema,
    kind: z.enum(['income', 'expense', 'transfer']),
    amount: positiveMoneyStringSchema,
    accountId: uuidSchema,
    transferAccountId: optionalUuid,
    categoryId: optionalUuid,
    payee: payeeSchema,
    notes: notesSchema,
    frequency: frequencySchema,
    intervalCount: z.coerce.number().int().min(1).max(365),
    startDate: isoDateSchema,
    endDate: z
      .union([isoDateSchema, z.literal(''), z.null(), z.undefined()])
      .transform((v) => (v ? v : null)),
    status: recurrenceStatusSchema.default('active'),
  })
  .superRefine((data, ctx) => {
    if (data.endDate && data.endDate < data.startDate) {
      ctx.addIssue({
        code: 'custom',
        message: 'End date must be on or after start date',
        path: ['endDate'],
      })
    }
    if (data.kind === 'transfer') {
      if (!data.transferAccountId) {
        ctx.addIssue({
          code: 'custom',
          message: 'Destination account is required',
          path: ['transferAccountId'],
        })
      } else if (data.transferAccountId === data.accountId) {
        ctx.addIssue({
          code: 'custom',
          message: 'Source and destination must differ',
          path: ['transferAccountId'],
        })
      }
    }
  })

export const goalFormSchema = z.object({
  name: nameSchema,
  targetAmount: positiveMoneyStringSchema,
  targetDate: isoDateSchema
    .optional()
    .nullable()
    .or(z.literal(''))
    .transform((v) => v || null),
  notes: notesSchema,
})

export const contributionFormSchema = z.object({
  amount: positiveMoneyStringSchema,
  contributedOn: isoDateSchema,
  notes: notesSchema,
})

export const debtFormSchema = z.object({
  name: nameSchema,
  accountId: uuidSchema,
  // Current balance comes from the linked liability account — not a form principal field.
  interestBps: z.coerce
    .number()
    .int('Interest must be whole basis points')
    .min(0)
    .max(100_000, 'Interest rate is unrealistically high'),
  minimumPayment: positiveMoneyStringSchema,
  dueDay: z.coerce.number().int().min(1).max(31),
  notes: notesSchema,
})

export const profileFormSchema = z.object({
  displayName: z.string().trim().max(80).optional().or(z.literal('')),
})

export type LoginInput = z.infer<typeof loginSchema>
export type SignupInput = z.infer<typeof signupSchema>
export type TransactionFormInput = z.infer<typeof transactionFormSchema>
export type AccountFormInput = z.infer<typeof accountFormSchema>
export type CategoryFormInput = z.infer<typeof categoryFormSchema>
export type BudgetFormInput = z.infer<typeof budgetFormSchema>
export type RecurringFormInput = z.infer<typeof recurringFormSchema>
export type GoalFormInput = z.infer<typeof goalFormSchema>
export type ContributionFormInput = z.infer<typeof contributionFormSchema>
export type DebtFormInput = z.infer<typeof debtFormSchema>

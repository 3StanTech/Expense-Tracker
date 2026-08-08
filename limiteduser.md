# Limited-user setup

## Current state

- The Fundsicles sign-in and signup pages remain publicly accessible.
- Public email/password signup remains enabled in Supabase.
- The site asks compliant search engines not to index pages or follow links through both an HTML `robots` meta tag and a site-wide `X-Robots-Tag` response header.
- `noindex` and `nofollow` reduce search discovery; they are not authentication or access-control mechanisms.

## Intended future setup

When Fundsicles is converted to a limited-user financial app:

1. Keep the sign-in page publicly accessible so approved users can log in normally.
2. Disable **Allow new users to sign up** in Supabase Auth. Existing users must remain able to sign in.
3. Replace the public signup experience with a clear invitation-only access message.
4. Invite approved users through **Supabase Dashboard → Authentication → Users → Add user → Send invitation**.
5. Keep email confirmation enabled and retain the existing exact production callback and reset-password URLs.
6. Continue monitoring Supabase Auth users as an audit measure, not as the primary membership restriction.
7. Preserve row-level security and verify that every authenticated user remains isolated to their own financial data.

## Not authorized yet

Do not disable signup, remove the signup page, introduce an email allowlist, change Supabase Auth policies, or alter invitation behavior until the user explicitly requests the limited-user conversion.

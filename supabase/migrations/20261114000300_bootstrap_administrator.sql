-- Owner-designated administrator. Supabase Auth must confirm this email before access is granted.
-- This creates an allowlist entry only; it never creates an account or bypasses sign-in.
insert into private.admin_emails(email)
values ('mueenptb@gmail.com')
on conflict(email) do nothing;

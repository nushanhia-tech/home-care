# Local Mate · Next.js + Supabase + Vercel

Local Mate is a local-services marketplace starting in Pattambi, Kerala. This version preserves the blue-and-white interface and the earlier Git history, and migrates the application from Sites/Cloudflare D1 to the requested stack.

- **Frontend and server:** Next.js 16 App Router, React, TypeScript server code.
- **Backend:** Supabase PostgreSQL, Auth, Row Level Security and Realtime.
- **Version control:** `https://github.com/nushanhia-tech/home-care`.
- **Deployment target:** Vercel, Mumbai region.

No live Supabase or Vercel project is hardcoded into the source. Projects and environment settings must be provisioned before account/booking features can run. The earlier private Sites publication remains a separate deployment and does not receive these Next.js changes.

## Working implementation

The UI includes service browsing/search, a town selector, distinct service/quotation/transport/goods/rental/emergency forms, customer profiles and addresses, provider applications, availability, booking acceptance/rejection, quotes and customer approval, job status history, booking-linked messages, notifications, completed-booking reviews, support tickets, admin provider/service/booking management, CSV exports and service summaries. No provider, review or transaction records are seeded.

Email magic-link sign-in uses Supabase Auth with PKCE and server-side session cookies. The Next.js proxy refreshes sessions; APIs call `auth.getUser()` again before authorization. Client role metadata never grants administrator access. Admin membership comes from `private.admin_emails` and requires a confirmed email. Administrator email addresses are configured privately in the database.

Database transactions lock booking rows for assignment, quote responses and status changes. PostgreSQL policies protect direct Supabase access as well as the Next.js routes. Only owned completed bookings can produce a verified review. Provider profile/contact data is private; the public provider view contains only approved professional details and real review aggregates.

Chat uses Supabase Realtime with polling as a fallback. Notifications are persisted in Supabase. Email sign-in is the only implemented external email flow; booking email/SMS/WhatsApp delivery is not claimed.

## Local development

Use Node.js 22 or 24.

```sh
npm ci
cp .env.example .env.local
# Add your Supabase project URL and publishable key to .env.local.
npm run dev
```

Open `http://localhost:3000`. With no Supabase environment variables, the app renders the starter catalogue and clear setup errors. It does not create local fake accounts, requests or payments.

### Create the Supabase project

1. Create a Supabase project in your account, preferably in an India region. Keep the database password in a password manager.
2. Copy its Project URL and publishable key into `.env.local` using the names in `.env.example`.
3. Apply the migrations and seed using the Supabase integration or CLI:

```sh
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push --include-seed
```

The migrations are in `supabase/migrations/` and must be applied in filename order. `supabase/seed.sql` adds the six launch towns and an editable starter catalogue. Administrator membership is configured separately; no personal administrator email is committed to source. It is idempotent and does not overwrite service edits. It never creates customers or service providers.

4. In Supabase **Authentication → URL Configuration**, set the production Site URL to the Vercel domain. Allow exactly `https://YOUR_DOMAIN/auth/callback` and `http://localhost:3000/auth/callback` for development. Configure explicit preview callback URLs when testing previews; avoid unrestricted wildcard domains.
5. Enable email sign-up, email confirmation and magic links. Configure production SMTP before inviting arbitrary customers: Supabase's default mail service has delivery restrictions and rate limits. Its template must use the Supabase confirmation URL so the callback receives a PKCE authorization code.
6. The project owner must insert the selected administrator email into `private.admin_emails` using the SQL below, then sign in with that confirmed email. Review provider identity/qualifications outside the app before approving their accounts.

To add another administrator, a project owner runs the following in Supabase SQL Editor; clients cannot run it:

```sql
insert into private.admin_emails(email) values (lower('another-admin@example.com')) on conflict do nothing;
```

Never grant admin access through `raw_user_meta_data` or client-side flags.

### Vercel deployment

1. Push the Git repository and tag to GitHub using an authorized account:

```sh
git push -u origin main
git push origin v0.2.0
```

2. Create a Vercel project by importing `nushanhia-tech/home-care`.
3. Select the **Next.js** preset and keep the root directory at the repository root. `vercel.json` sets `npm ci`, the Next.js build, and region `bom1`.
4. Add these variables to the appropriate Production/Preview/Development environments:

| Variable | Location | Purpose |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Vercel and local development | Supabase Project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Vercel and local development | Browser-safe public key; RLS remains required |
| `NEXT_PUBLIC_SITE_URL` | Vercel and local development | Exact app origin used in email callbacks |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only, optional | Verified payment integration only |
| `RAZORPAY_KEY_ID` | Server only, optional | Payment gateway identity |
| `RAZORPAY_KEY_SECRET` | Server only, optional | Payment gateway authentication |
| `RAZORPAY_WEBHOOK_SECRET` | Server only, optional | Signed capture verification |

5. Deploy, update Supabase's production callback URLs, and verify email sign-in and role-specific workflows. Do not point preview deployments at a production database when exercising destructive tests. Use a separate Supabase project or branch.

Vercel's Git integration creates previews for pull requests and deploys changes to `main` to production. No token needs to be committed to GitHub. The CI workflow in `.github/workflows/ci.yml` checks types, database rules and the Next.js build without live credentials.

## Verification

```sh
npm run typecheck
npm test
npm run build
```

The database suite executes the actual migrations, SQL functions, grants and RLS policies in an isolated embedded PostgreSQL instance (PGlite). It tests admin membership, provider eligibility, exclusive/idempotent assignment, quote approval, conversation privacy, completed-booking reviews, address/favourite/notification policies, server-only payment capture and write rate limits. Test users and records never touch a live Supabase project.

A production Next.js build and a local Chromium desktop/mobile smoke test were also run during migration. To repeat the UI check with Supabase variables unset and the app running, install Python Playwright and run `python3 tests/ui-smoke.py`; the script writes screenshots to `/tmp/local-mate-qa` by default and refuses a configured backend before any sign-in request. Live Supabase email delivery, Realtime subscriptions and Vercel deployment still require connected projects and verification in those accounts.

### Payment integration

`/api/payments/order` creates a gateway order only for an owned completed booking; the amount comes from PostgreSQL. `/api/payments/webhook` verifies Razorpay's HMAC signature, checks the captured INR amount, and calls a service-role-only transaction. Duplicate capture notifications do not duplicate records. Ordinary users cannot mark a payment successful through direct table writes or RPC calls.

Online checkout UI, refunds, cash reconciliation, payouts and commission accounting remain unfinished. Keep payment credentials unset until sandbox testing and the customer checkout are completed. Cash bookings remain pending without reconciliation; completed job value is not an available bank balance.

## Repository structure

```text
app/                    Next.js layout, client page, API route and auth callback
lib/api.ts              API handlers, validated sessions and gateway webhook
lib/supabase/           Cookie-based server client, browser client, payment-only admin client
src/main.jsx            Existing marketplace UI, adapted for Next.js and Supabase
src/style.css           Responsive blue/white design system
src/catalog.js          Starter catalogue and frontend workflow labels
public/assets/          House illustration and licensed service icons
supabase/migrations/    PostgreSQL schema, RLS and transactional business rules
supabase/seed.sql        Initial towns and editable service catalogue
supabase/config.toml    Local Supabase configuration
proxy.ts                Supabase session refresh
.github/workflows/      Automated checks
vercel.json             Vercel deployment settings
```

The initial public-schema migration revokes default table/function access before granting the narrow permissions required by clients. Its helper functions use an empty search path and fully qualified references. Private functions are not exposed as client operations. Future database changes should be new migrations; do not rewrite an applied migration.

## Current limits

This is the migrated core application, not every advanced feature in the master brief. Secure document/photo/video uploads, provider teams, granular support/super-admin roles, automated timeouts/reassignment, map/geocoding/radius logic, GPS tracking, full Malayalam translation, favourites management UI, review moderation, coupons/subscriptions, invoice PDFs, refunds/payouts and commercial policy finalization remain to be implemented.

Provider online status and maximum daily acceptance capacity are enforced. Free-text working-day/hour/holiday fields are coordinator-facing details, not a full scheduling engine. A provider application does not itself establish legal identity or qualifications. Policies shown in the UI are launch drafts. Admin commission settings currently save a percentage without initiating charges.

Service icons: Microsoft Fluent Emoji, MIT. See `public/assets/ATTRIBUTION.txt`. The house illustration is an original SVG.

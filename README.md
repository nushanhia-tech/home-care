# Local Mate

A local-services marketplace built with Next.js, Supabase and Vercel. The repository preserves the earlier Local Mate history and blue-and-white interface.

## Set up username/password login

1. Open [supabase/setup.sql](supabase/setup.sql), copy the **entire** file into your Supabase project's SQL Editor, and run it as the project owner. The file installs the schema, row-level security, transactional booking workflows, administrator bootstrap state, website settings and initial services/towns. It can be rerun for this schema without deleting customer records or edited catalogue prices.
2. In Vercel → Project → Settings → Environment Variables, configure:

| Variable | Purpose |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase Project URL, without `/rest/v1/` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Browser-safe project publishable key |
| `NEXT_PUBLIC_SITE_URL` | Production website origin |
| `SUPABASE_SECRET_KEY` | **Server-only** Supabase secret key for account management; `SUPABASE_SERVICE_ROLE_KEY` is also accepted |
| `ADMIN_INITIAL_PASSWORD` | Optional initial administrator password; defaults to the requested `admin123` |

Never prefix the service-role key with `NEXT_PUBLIC_`, include it in source, or put it in a publicly downloadable file. `.env.example` and `downloads/final.env` contain placeholders only for server secrets. Fill the real server key directly in Vercel. Modern secret keys use the `apikey` header; legacy service-role JWTs retain Bearer authentication. The server normalizes copied quotes/assignments and verifies configured candidates against the account-setup RPC before using them. Redeploy after changing environment variables.

3. Open `/admin` on the deployed website. Sign in with username **admin** and the configured initial password (**admin123** by default). The server provisions this account once using Supabase Auth's supported Admin API. It never resets an existing administrator to the default password.
4. At the first login, change the temporary password to a different password of at least 12 characters before administrator controls unlock. You can change the username at the same time or later in Settings.

Email-link sign-in and email verification are not part of the application login flow. Customers register with a name, username and password. The server creates confirmed Supabase Auth accounts using internal identifiers and checks passwords through Supabase Auth. No verification emails are sent. Supabase Auth sessions and RLS still protect all account data; the application never accepts a client-provided administrator role.

Existing customer data and Auth accounts are preserved by the migration. Older email-only accounts need a username and temporary password assigned through Admin → Users before they can use the new sign-in screen. Those users must change their temporary password after login. The earlier owner-selected email allowlist remains for existing authorized identities; it does not replace password authentication.

## Administrator controls

- Overview, bookings, provider creation/editing, approval/suspension, manual provider assignment and service management. Add providers with a new username/temporary password or convert an existing customer account. New accounts must change their temporary password on first login. Set service-specific INR prices (per visit/hour/day or quote), coverage, public-phone consent and an optional sourced assessment rating. Verified booking review averages remain separate.
- Users: suspend/reactivate accounts and assign usernames/temporary passwords. An administrator cannot suspend their own active account through this screen.
- Website & portals: website name, announcement, hero text, tagline, contact information, About, FAQ and policy text. Pause the public website, customer/provider portals, registration or new bookings. Administrator access remains available during maintenance. New-booking and provider-job restrictions are also enforced in PostgreSQL.
- Services: manage the providers offering each service, their rates and actual provider counts. Counts reflect saved provider records; public counts include approved active accounts in the selected town.
- Locations: add, activate and pause service towns, view provider counts and add/remove providers from each area.
- Settings: change your own username/password using your current password; save the commission percentage. Commission settings do not initiate charges or payouts.
- Backup: download a JSON export of marketplace profiles, providers and their service prices, catalogue, locations, bookings, messages, reviews, payments, support, website settings and activity logs. **Passwords, Auth sessions, storage files, live GPS positions/session identifiers and project secrets are excluded.** For a full infrastructure restore, use Supabase's project backup tools. There is no in-app Auth/password restore from the JSON export.
- Delete all data: requires your current password and the exact phrase `DELETE ALL DATA`. Removes marketplace records and all other Auth accounts while preserving the current administrator login. The website and registration stay paused until you reopen them in Website & portals. Account deletion uses Supabase's Admin API. A partial account-cleanup failure is reported and can be retried; it is never reported as a fully successful wipe. Removing payment records does not refund bank transactions. Download an appropriate backup before using this option.

Adding the reset feature does not execute it. No hosted data is removed by installing these migrations or deploying the application.

## Customer and provider workflows

Customers can browse/search services, select a town, manage profiles/addresses, request service-specific bookings, approve quotes, view status history, message assigned professionals, submit completed-booking reviews, and open support tickets. Providers apply for approval, control online availability, accept/reject matching requests, send quotations and progress jobs. No fabricated providers, reviews or transactions are seeded.

Booking assignment and quotation responses use PostgreSQL row locks. A job has one primary assigned provider. The public directory shows a phone number only with explicit provider consent. Private contact numbers are available to the customer and assigned provider, plus authorized administrators, through a participant-checked booking endpoint. Chat uses Supabase Realtime with a polling fallback. In-app notifications are persisted; external SMS/WhatsApp/push delivery is not configured. Provider and customer portals include a booking-linked messages inbox; request lists refresh while the page is open.


### Provider directory and exact places

Open a service to see all approved providers serving the selected town, their phone (when consented), verified reviews, separately labelled sourced assessment, availability and service rate. Select an online professional to send them the first request. Their per-visit price becomes the estimate. Hourly, daily and quote pricing require customer approval of the total quotation before confirmation. If a selected provider declines, other matching professionals can respond with a quotation. Administrators can add providers and prices in **Providers**, manage service membership in **Services → Manage providers**, and manage coverage in **Locations**.

Customers can save a written address and an optional exact map pin, then reuse it when booking. Transport/goods bookings accept a separate written destination and destination pin. Use GPS explicitly or click/drag a marker. A map's initial town center is not a selected location. Leaflet displays attributed OpenStreetMap tiles without a commercial map API key. No automatic reverse geocoding, road routing or invented travel times are used; directions links open Google Maps. GPS coordinates do not replace the required written address.

### Live provider GPS

Open an assigned active booking in the provider portal and choose **Share my live GPS for this job**. The browser asks for location permission. The customer opens that booking in My bookings to see the latest position, timestamp and accuracy alongside the service/destination pins. HTTPS and a device/browser with location support are required; Vercel's production URL supports HTTPS.

Sharing is **foreground only**. It stops when the provider hides the page, closes the booking, selects Stop, or the job finishes/cancels. Background/mobile-lock tracking and guaranteed arrival estimates are not provided. GPS uploads are throttled, the customer refreshes every five seconds, and positions older than two minutes disappear from view. Session identifiers invalidate delayed uploads after Stop, and an old tab cannot stop a newer sharing session. The server checks the assigned provider and active booking, and customer/admin reads are participant checked. Only the latest point is kept; explicit Stop and terminal/reassignment transitions delete it. If the browser is killed without delivering Stop, the last point becomes stale and remains stored until cleanup at the job's next terminal/reassignment transition. No position history is stored or included in application backups.

### Upgrade an existing deployment

Apply the latest complete [supabase/setup.sql](supabase/setup.sql) in the project's Supabase SQL Editor, or apply `20261115000100_provider_directory_tracking.sql` using your established migration workflow. The update preserves accounts, bookings and catalogue edits. Git/Vercel deployment alone does not run Supabase migrations. Missing-schema responses name the setup file to run. Existing providers receive quote-only offerings during migration; enter actual rates through the provider or administrator profile editor. No prices, provider reviews or GPS positions are fabricated.

## Local development

Use Node.js 22 or 24:

```sh
npm ci
cp .env.example .env.local
# Fill Supabase values and the server-only account-management key.
npm run dev
```

Without Supabase configuration, the starter catalogue renders and private actions show setup errors. Without the server-only key, username registration, login/bootstrap and credential management remain unavailable. No fake local accounts or successful payments are created.

### Supabase CLI alternative

Use either the one-file SQL Editor setup or the CLI workflow:

```sh
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push --include-seed
```

If switching to CLI after manual setup, mark the already installed migration versions applied using `supabase migration repair` after verifying the schema. Do not rewrite applied migrations. `supabase/seed.sql` is idempotent and preserves service edits.

The single setup file is generated from migrations:

```sh
npm run db:setup:generate
npm run db:setup:check
```

## Vercel and Git

Import `nushanhia-tech/home-care` with the Next.js preset and repository root. `vercel.json` specifies `npm ci`, the production build and Mumbai region. Add the environment variables above, then deploy. The Git integration deploys changes pushed to `main`; GitHub Actions checks types, SQL setup consistency, tests and the build.

The original private Sites publication is separate and does not receive these Next.js deployments. Real Supabase/Vercel settings require access to those accounts; publishing source or SQL does not itself apply a hosted database migration.

## Verification

```sh
npm run typecheck
npm run db:setup:check
npm test
npm run build
```

The SQL suite runs the actual migrations and row-level security in isolated embedded PostgreSQL (PGlite). It covers authorization, idempotent/exclusive booking assignment, quotation approval, conversation privacy, eligible reviews, username mappings, one-time admin bootstrap, required password rotation, suspension, portal switches, backups, reset confirmation, provider rate/coverage editing, preferred-provider matching, coordinate validation, private contacts, GPS consent/ownership, stale positions, and stopped-session invalidation. Test records never reach the live database.

`tests/ui-smoke.py` checks the unconfigured-backend experience, search, responsive layouts and login dialogs. `tests/admin-ui.py` uses mocked API responses to check username login, first-login password changes, website controls, backup download and explicit reset confirmation. `tests/marketplace-ui.py` covers adding a provider, service/area counts, provider selection, prices, map pins, customer contact/tracking, provider messaging and GPS start/stop with local mocked APIs and simulated device coordinates. These tests never send emails or modify hosted data. `tests/provider-settings-ui.py` checks availability/profile navigation with native, legacy, missing and malformed JSON values, preserves edits across saved-profile refreshes and slow requests, and verifies failed saves remain recoverable.

Live password authentication and account creation still require the configured server key and must be verified against the connected Supabase project.

## Optional payments

Configure `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` server-side only. `/api/payments/order` reads the amount from an owned completed booking. `/api/payments/webhook` validates Razorpay's signed capture, checks the exact INR amount, and calls a service-role-only transaction. Duplicate capture events do not duplicate payment records. Browser requests cannot mark payments successful.

Online checkout UI, refunds, cash reconciliation, payout processing and actual commission accounting remain unfinished. Cash bookings stay pending without reconciliation. Completed job value is not a bank balance.

## Remaining platform limits

Secure document/photo/video uploads, provider teams, granular support/super-admin roles, automatic request expiry/reassignment, automatic geocoding/service-radius matching, background GPS tracking, full Malayalam translation, review moderation, coupons/subscriptions, PDF invoices and a full backup-restore UI remain to be implemented. Working-day/hour/holiday text is coordinator-facing; provider online state and daily acceptance capacity are enforced. Finalize legal policies before commercial launch.

Service icons: Microsoft Fluent Emoji, MIT; see `public/assets/ATTRIBUTION.txt`. The house illustration is an original SVG.

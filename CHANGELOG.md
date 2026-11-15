# Changelog

## 0.4.1 — 2026-11-15

- Fix provider Availability/Profile crashes when saved settings are null, malformed, native JSONB or legacy JSON text.
- Normalize provider collections and settings at the API and form boundaries, keeping valid existing values.
- Preserve availability drafts during refreshes/slow saves and show newly saved provider rates after account refresh.
- Add provider settings regression coverage for repeated desktop/mobile tab navigation, data formats and failed-save retry. No database migration is required for this patch.

## 0.4.0 — 2026-11-15

- Add administrator provider creation/editing, temporary username credentials, service-specific prices, coverage controls and consented public contact numbers.
- Add public service provider counts, rates and provider selection; keep sourced assessments separate from completed-booking reviews.
- Replace ambiguous provider/profile relationship queries with explicit directory joins and improve missing-schema diagnostics.
- Add provider profile/rate management and customer/provider messages inboxes, keeping existing quotations, booking progress, support and account controls.
- Add saved service/pickup/destination map pins and directions links, with explicit GPS permission controls.
- Add private foreground provider GPS with assigned-job authorization, freshness limits, session invalidation on Stop and cleanup on terminal/reassignment events.
- Add additive database migration and regenerate complete setup SQL. Backups include provider prices and exclude live GPS/session tokens.
- Verify SQL authorization/workflows, production build and local desktop/mobile browser flows with mocked APIs; no live test accounts or location records are created.


## 0.3.0 — 2026-11-14

- Replace email links with username/password accounts backed by Supabase Auth.
- Add one-time administrator bootstrap with mandatory initial password rotation.
- Add website/portal controls, location management and account suspension/credential management.
- Add application-data backup downloads and reauthenticated, confirmed marketplace/account deletion.
- Add direct administrator, provider and account pages.

## 0.2.0 — 2026-11-14

- Migrate the existing UI to Next.js 16 App Router and a Vercel deployment configuration.
- Replace Sites identity and Cloudflare D1 with Supabase Auth, PostgreSQL, RLS and Realtime.
- Keep the earlier Local Mate commits as repository history.
- Add transactional booking assignment, quotation approval, status changes and server-only payment capture.
- Add PostgreSQL policy tests and GitHub Actions checks.
- Preserve the existing public/private portals, service-specific forms and responsive design.

## 0.1.0

- Initial Local Mate implementation and private Sites publication, preserved in Git history.

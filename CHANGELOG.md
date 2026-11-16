# Changelog

## 0.5.0 — 2026-11-16

- Broadcast requests to all eligible providers with row-locked, single-winner acceptance and assignment history. Reopen declined quotations safely.
- Remove counterpart phone numbers from public/participant responses and raw database access; add private image uploads, re-encoding and administrator privacy review.
- Require server-generated, hashed/encrypted, expiring work-start OTP verification; add audited administrator exceptions.
- Add approved extra charges, exact final billing, customer confirmation/disputes, real PDF invoices and verified payment/refund records.
- Add weekly commission snapshots, provider/category overrides, payment proof submission, explicit admin verification and earned-overdue-only new-job restrictions/reactivation. Zero-job providers remain eligible.
- Add real booking-authorized WebRTC audio, incoming call controls, mute/output selection, duration/history, secure signalling and temporary Coturn credentials. No audio recording.
- Expand all three portals, audit/backup coverage, maintenance scheduling and production Coturn guidance.
- Verify unit/database checks, real PostgreSQL concurrency and actual Chromium media transport. Hosted SQL application, production TURN/TLS and external-network checks remain required deployment steps.

## 0.4.2 — 2026-11-15

- Fix administrator tab request races: Providers only renders results belonging to its current account, tab and refresh, and ignores delayed responses from other screens.
- Keep provider list failures inside the dashboard with a retry action and safely handle incomplete provider metadata.
- Fetch overview statistics independently from tab lists so unrelated failures cannot replace provider results.
- Add administrator regression checks for delayed requests in both orders, correct provider approval targets, invalid directory responses, retry and desktop/mobile navigation.

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

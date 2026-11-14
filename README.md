# Local Mate

A responsive local-services marketplace for Pattambi and nearby Kerala towns, styled after the supplied blue-and-white home-services reference.

## What works

- React interface: home, searchable category catalogue, provider directory, service-specific booking forms, customer account, provider portal, protected administrator portal, support and policy screens.
- Sites-authenticated accounts. Server authorization derives identity exclusively from Sites-verified headers. Administrator access is controlled by the secure `ADMIN_EMAILS` setting. Clients cannot grant themselves roles.
- D1 relational storage, foreign keys, indexes and a checked-in schema migration. No fabricated providers, reviews, customer bookings or transactions are seeded.
- Editable services with fixed, quotation, transport, goods, rental and emergency flows. An administrator initializes the starter catalogue with the button in Admin → Overview, then edits or adds services through Admin → Services.
- Indian phone profiles, customer-owned saved addresses, supported-town selection, location/service/verification/online-state matching, future-date validation, idempotent booking requests and an atomic single-provider acceptance guard.
- Provider applications and approval, online/offline state, accept/reject, quotations, customer quotation approval/rejection, sequential job states, timestamped history, customer cancellation/rescheduling and manual admin assignment.
- Booking-scoped text messages with 10-second refresh, persisted in-app notifications, support tickets and administrator responses. No claim of external message delivery is made.
- One verified review per completed booking, approved-provider ratings, favourites API, CSV booking/earnings exports, and downloadable service summaries clearly distinguished from proof of payment.
- Server-side Razorpay order creation and HMAC-verified capture webhook with amount/currency validation. Browser assertions never mark a payment successful. Cash bookings remain pending without reconciliation.
- Server-side request validation, cross-origin write protection, role checks and a per-user write limit of 60 requests/minute.

## Launch

1. Sign in to the private Site using the administrator email configured by the owner.
2. Open Admin portal in the footer → Initialize service catalogue.
3. Pros sign in, complete a profile with an Indian phone number, and apply through Become a pro.
4. Review identity and any required qualifications outside the app before approving a provider in Admin → Providers.
5. Approved providers set themselves online under Availability. Customers can then create requests for matching services and towns.
6. Providers accept or submit a quote. Customers approve quotation-based work before the job progresses.

The site is private by default. A public commercial launch requires an explicit audience change plus completion of the items below.

## Architecture

`src/main.jsx` contains the React pages, forms and dialogs; `src/style.css` contains the responsive design system. `src/worker.js` provides the HTTP API, identity checks and booking rules. `src/catalog.js` holds an initial editable service catalogue and workflow definitions. `migrations/0001_initial.sql` declares users, provider profiles, services, addresses, bookings, status history, rejections, quotations, messages, notifications, reviews, payments, support tickets, favourites, settings, audit logs, upload metadata and write-limit windows.

The app builds into a Cloudflare Worker ES module, with the React document and local assets bundled into it. Hosting provisions the D1 `DB` binding. Google Fonts provide DM Sans and Manrope; system fonts are fallbacks. The service illustrations use Microsoft's Fluent Emoji (MIT); the house is an original SVG.

## Development and checks

Node 24+ and npm are required.

```sh
npm ci --cache /tmp/local-mate-npm
npm run build
npm test
```

The tests use an isolated in-memory SQLite database through a D1-compatible adapter and exercise authorization, catalogue initialization, provider eligibility, idempotency, exclusive assignment, rejections, quote approval, message privacy, eligible reviews, payment integrity and address ownership. Test identities and records never reach the hosted database.

Managed preview needs the platform `sites-preview` and `cua_repl.js` browser tooling. This workspace did not expose `cua_repl.js`, so browser QA was not performed. Build and API tests are independent of browser availability.

## Runtime configuration

Set secrets through Sites environment settings. See `.env.example` for names; do not commit actual values. `ADMIN_EMAILS` accepts a comma-separated list. `DB` is a database binding. The migrations must be deployed before traffic reaches a new database. Never expose the Worker directly without Sites' authenticated header boundary.

For Razorpay, configure all three values: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET`. Point the signed capture webhook to `/api/payments/webhook`. Test in the gateway's sandbox before using live credentials. `/api/payments/order` creates an order for an owned completed booking; the capture webhook alone verifies a successful payment. The customer checkout UI is not enabled yet.

## Remaining work before production commercial use

This is a working foundation and core booking application, not a completed production platform covering every item in the master brief.

- Phone OTP/email authentication is not configured; hosted ChatGPT sign-in is implemented.
- Payment checkout UI, refunds, cash reconciliation, actual commission accounting, payout processing, subscriptions and coupons remain to be implemented. The commission screen currently saves a configuration value only. Statements show completed job values, not bank balances.
- Secure document/photo/video uploads, document review workflows, provider teams and granular support/super-admin roles remain to be implemented. Do not collect identity/bank documents in plain text forms.
- Messaging is stored text with polling, not WebSocket realtime. Attachments, read receipts, block/report controls and external email/SMS/WhatsApp/push delivery need integrations.
- Locations currently use the six initial towns. Map/address autocomplete, distance pricing, service-radius geometry, administrator location management and consent-based GPS tracking are not implemented.
- Online/offline state gates requests; detailed schedule fields are coordinator-facing information, not an automatic capacity/holiday scheduling engine. Automatic request expiry/reoffer and provider-request timeouts remain to be implemented.
- Favourites are saved through an API; a favourites management screen remains to be added. Business/team accounts, advanced provider editing, notification deep-links, review moderation and detailed reporting require expansion.
- Navigation includes basic Malayalam labels. Full Malayalam content and a translation catalogue remain to be completed.
- Legal policy screens are clearly marked launch drafts. Finalize business identity, contact details, service terms and data-retention/deletion procedures. Perform accessibility/browser testing, security review, load testing and payment sandbox testing before a public launch.

These limitations are shown where they affect a decision; unavailable integrations do not manufacture successful transactions, notifications, providers, reviews or GPS positions.

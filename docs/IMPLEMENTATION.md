# Local Mate 0.5.0: implementation and verification

The actual backend, SQL policies/transactions and all three portals implement request broadcast/atomic acceptance, private contacts/chat/media, customer work-start OTPs, approved billing/PDF invoices, weekly commission verification/restrictions and real WebRTC audio. Existing `bookings` and `messages` remain the canonical request/conversation records; additive offer, assignment, verification, finance, read-status, media, event and audit records extend them rather than duplicating their identity.

## Verified locally

- `npm run check`: TypeScript, 53 tests, production Next.js build.
- `npm run db:setup:check`: generated SQL matches migrations. Setup tests install fresh and rerun without deleting records.
- `npm run test:operations`: PostgreSQL 17, separate concurrent connections. Five providers receive the request; one simultaneous winner; counterpart contacts hidden; OTP cannot be bypassed; approved additional charges only; INR 1,200 actual bill and one invoice; INR 10,000 at 10% equals INR 1,000; screenshots do not approve payment; overdue earned commission restricts new requests; no-job provider remains eligible; bank verification reactivates; disputes hold commission; unrelated booking/chat access denied; quote rejection reopens distribution; verified refunds cannot exceed real paid funds.
- `tests/voice-real-ui.py`: actual Chromium microphone/RTCPeerConnection audio through Next API, PostgreSQL/PostgREST and Coturn, in both call directions; received audio bytes and forced relay candidate statistics; mute tracks; call history; private booking/call/signal permissions; microphone denial; reject/logout; protected real PDF bytes; real image re-encoding/private storage/review; chat and phone blocking with calling disabled.

The test Auth and Storage adapters run only on loopback; they isolate account provisioning/storage from hosted services while the application, SQL, authorization, PDF, image transformation and WebRTC media execute normally. Test microphone input is a generated tone. The application itself has no fake calling mode and never records that audio. Local TURN checks verify actual relay transport, not production carrier connectivity.

## Activation boundaries

Committing/pushing code does not apply SQL to the hosted Supabase project. Apply the complete `supabase/setup.sql` and optional `supabase/scheduler.sql`; set server-only OTP/TURN secrets; enter actual business payment instructions; provision a public Coturn host/certificate/firewall; redeploy and test two devices across the intended networks. See [setup, costs and privacy](VOICE-OPERATIONS-SETUP.md).

No production SMS, WhatsApp, closed-website push, bank transfer/refund, invoice tax registration, storage bucket, TURN VM or external carrier/TLS connectivity is claimed by the local checks. No real accounts, payments or hosted data were modified by the integration tests. Browser speaker selection depends on native support. Foreground GPS and optional configured payment gateway retain their documented limitations.

Account phone columns are owner/admin-only. Shared text rejects recognizable phone formats and user images require review; deliberately encoded contact information cannot be made mathematically undiscoverable in arbitrary text/pixels. Official clients close media on logout/session/booking revocation. Strict media enforcement against colluding modified peer-to-peer clients requires a controlled SFU rather than ordinary WebRTC.

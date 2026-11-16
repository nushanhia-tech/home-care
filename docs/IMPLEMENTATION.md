# Local Mate operations and private voice calling

This release replaces selected-provider routing with atomic, all-eligible-provider distribution. It adds server-verified work-start OTPs, approved billing and PDF invoices, weekly commission accounting/payment verification, private media, and real WebRTC audio.

Implementation and acceptance checks are tracked in `tests/operations*.mjs` and the browser integration scripts. No hosted migration, TURN deployment, payment, recording, or external notification delivery is implied by committing this source. Hosted setup and exact verified results are documented in the release notes once checks finish.

Phone privacy covers stored account contacts and structured API/database access. Text contact sharing is blocked/redacted and images require privacy approval before being shared. No software can guarantee that a user will never deliberately encode contact information into arbitrary text or image pixels; moderation remains required.

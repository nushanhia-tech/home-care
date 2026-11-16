# Local Mate activation and cost model

1. Apply the complete `supabase/setup.sql` in the existing project's SQL Editor as owner. It is generated from additive migrations. Back up the project first. Do not expose a database password, service-role key, OTP key or TURN shared secret in browser variables or source.
2. Set `OTP_HMAC_SECRET` to a stable random 32+ character server secret in Vercel. The backend can derive an OTP key from the existing server key for compatibility, but a separate stable OTP key is recommended. Existing issued OTPs expire if their key changes.
3. In Admin → Booking, OTP & calling, configure the weekly timezone/start day, commission rates, real business payment account and deadline/grace policy. The initial timezone is Asia/Kolkata. Periods begin when a completed job becomes billable through confirmed billing. Recorded periods cannot be silently changed or overlapped. Provider/category overrides affect future commission snapshots only.
4. Run `supabase/scheduler.sql` as project owner to schedule expiry, commission-status notifications and housekeeping every five minutes. Dynamic eligibility already blocks overdue earned commission without depending on scheduler timing. Alternatively call GET `/api/cron/maintenance` with `Authorization: Bearer <CRON_SECRET>` from a trusted scheduler. No jobs means no commission debt or non-payment restriction. Blank business-payment instructions never cause a commission restriction.
5. The private `local-mate-private` Storage bucket is created by setup on Supabase. Images are re-encoded as JPEG without source filenames/EXIF and served through authenticated, role-checked requests. Sharing job/chat/logo images requires an administrator privacy review. Commission proofs remain visible only to their owner and administrators; approving an image is separate from verifying a bank payment.

## Real internet voice calls

The application uses RTCPeerConnection/getUserMedia audio, authenticated booking-scoped SDP/ICE signalling and ephemeral TURN credentials. There is no telephony API or per-minute mobile-call charge. No MediaRecorder is used, microphone audio is not uploaded/stored, and administrators see metadata only. Microphone permission and HTTPS are required. Browser/device controls may be needed for speaker/headset selection on browsers that do not implement setSinkId. Incoming calls work while the website is open; guaranteed delivery to a closed website needs a separately configured push service. In-app messages remain available if calls fail or are disabled.

WebRTC/STUN/Coturn are free/open-source components. Internet data, Vercel/Supabase usage, a public TURN server, TLS certificate operations and relay bandwidth can incur costs. Free hosting quotas are not a promise of zero operating cost. A TURN relay commonly handles both upload and download media traffic for each relayed call; measure real audio bitrate, concurrent allocations and provider billing before estimating monthly egress. At scale, monitor bandwidth, CPU, active allocations, API/Realtime quotas and availability; use multiple relays/regions and adapt signalling delivery to actual concurrency.

### Self-hosted Coturn

Vercel does not host a persistent UDP/TCP TURN daemon. Use a separate public Linux host. Configure a DNS-only hostname and valid certificate/key at `infra/coturn/certs/fullchain.pem` and `privkey.pem`, readable by the container user. Copy `.env.example` to `.env` in that directory, fill the real hostname/IP/secret, then run `docker compose up -d`. The production template rejects loopback/private peer targets and never enables an unauthenticated open relay.

Open TCP/UDP 3478, TCP 5349 and the configured UDP relay range 49160–49260 in the host/network firewall. Increase the relay range and capacity for production concurrency. If the host is behind NAT, configure Coturn's external/public-to-private IP mapping correctly. Restrictive networks may need TURN/TLS on a dedicated 443 listener; reserve that port on the relay host and update the URL/firewall. An HTTP reverse proxy or proxied Cloudflare DNS entry does not relay TURN UDP/TCP automatically.

Set server-only Vercel variables:

```
STUN_URLS=stun:turn.example.com:3478
TURN_URLS=turn:turn.example.com:3478?transport=udp,turn:turn.example.com:3478?transport=tcp,turns:turn.example.com:5349?transport=tcp
TURN_SHARED_SECRET=<the same private Coturn secret>
```

Redeploy after environment changes. Never prefix the shared secret with NEXT_PUBLIC_. The browser receives short-lived, authenticated TURN credentials for its own authorized call, never the shared secret. Admin's relay-only option refuses calls if relay credentials are missing. Until a relay is operated, direct/STUN calls can work on compatible networks, and a failed connection offers retry/chat without revealing phone numbers.

## Privacy boundary

Stored provider/customer phone numbers stay private to the owner and authorized administration. They are absent from counterpart/public directory, booking, chat, signalling, call and invoice responses. New shared text rejects recognizable Indian phone-number formats and legacy text is redacted. User-generated images are moderated before sharing. Deliberately obfuscated text or hidden information in image pixels cannot be guaranteed impossible by software; human moderation remains necessary.

Call/session revocation is enforced by the official client stopping tracks/closing peer connections and server heartbeat/status/booking checks. Hard media termination against modified, colluding WebRTC clients would require a server-controlled SFU/media relay, beyond ordinary peer-to-peer WebRTC. Metadata/signalling authorization remains server enforced.

## Actual deployment prerequisites

Source deployment does not apply a hosted Supabase migration, configure real bank details, enable a database scheduler, provision a public Coturn VM/certificate or verify carrier-network connectivity. Complete those owner-side steps before describing the hosted feature as fully activated. External cellular/Wi-Fi/TLS connectivity must be verified against the operator's real TURN host; local forced-relay tests do not replace that network check.

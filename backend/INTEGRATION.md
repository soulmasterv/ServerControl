# Ubuntu agent required before Services becomes live

This repository did not contain the live backend. No Ubuntu access was available.
`services_adapter.py` is a reviewed integration component, not a drop-in replacement
or a claim that the live backend was inspected/deployed.

1. Inspect `/home/local/ios-swift-app/server_control.py` on Ubuntu and back it up.
   Compare its existing routes, auth and runtime against the app contract; preserve
   dashboard, PM2 and Docker behavior. Do not replace the working server wholesale.
2. Import one ServicesAdapter instance into that process. Route the three paths
   below AFTER the existing constant-time bearer-token authentication. Never pass
   `authenticated=True` based on client data. Use the existing HTTP response writer.
3. Inject a bounded/cached `reader()` returning the normalized dictionaries consumed
   by snapshot(). Inspect the real Gemini monitor API and existing authentication.
   Use its existing credentials server-to-server from protected local configuration.
   Map all 10 keys to key-1…key-10; no upstream raw JSON, names containing keys,
   credentials, exception text or environment variables may enter the public response.
4. Map Classera 1/2/3 scheduler, webhook, last-run and last-report timestamps. Register
   individual fire callbacks only after verifying the existing allowlisted operations
   and intended recipients. Do not modify the scheduled automation. Callbacks receive
   no client arguments. Report WhatsApp billing/payment problems separately from Padel
   watcher/bot/dashboard application health. Preserve Gemini monitor authentication.
5. Register Gemini tests individually after inspecting the actual monitor API. Keep
   network timeouts short and cache monitor reads to avoid slowing `/api/dashboard`.
   Prefer nonblocking job enqueue if a test/report is slow; report its last result on
   subsequent GETs. A command is never automatically retried by iOS.
6. Test unauthenticated requests, unknown IDs, secret redaction, backend errors and
   command deduplication using stubs. Do not fire real WhatsApp reports during tests.
   Deploy/restart only the existing ServerControl process using its normal method.
   Verify the public domain health and authenticated dashboard/Services afterwards.

## Routes

- GET `/api/services`: JSON schema in `ServerControl/ServiceModels.swift`; timestamps
  are ISO 8601 strings. Missing provider returns 501 and the app shows a service-only
  availability message. Missing data reports Unknown rather than invented health.
- POST `/api/services/gemini/{key-1…key-10}/test`: bearer-authenticated predefined test.
- POST `/api/services/classera/{classera-1…classera-3}/fire`: bearer-authenticated
  predefined real WhatsApp report. The app asks explicit confirmation then device
  authentication immediately before the POST. LocalAuthentication is a local privacy
  gate, not server-verifiable authentication; server bearer auth remains mandatory.

Do not add a shell/SSH endpoint, Docker socket exposure, router forwarding, new public
ports, or put local configuration/credentials in GitHub. Adapter action cooldown is
30 seconds to suppress duplicate messages, independent of dashboard refresh.

## Signing and notifications

The pipeline creates an unsigned arm64 IPA for SideStore to re-sign. It does not
provision an Apple Developer push certificate, App ID push capability or APNs
entitlement. Remote APNs is therefore not implemented in this free-signing setup.
Only useful local notification testing remains visible; the event/preference types
remain available for a separately provisioned future transport. Do not add an
`aps-environment` entitlement without the required signing/provisioning change.

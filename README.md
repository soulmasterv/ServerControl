# Server Control V3

An incremental SwiftUI iOS 17 update to the existing ServerControl app.

## V3 update

Incremental update: full-app device authentication and background privacy lock,
coalesced/cancellation-safe refresh, protected cached dashboard snapshots, production
domain with trusted Tailscale GET fallback, compact inline PM2 search and transient
command notices, and extensible Services pages. PM2/Docker cards and controls remain.
No bearer token is sent outside the two explicitly trusted ServerControl endpoints.
POST commands never fail over or retry automatically. A reachable fallback stays
selected for five minutes; this is endpoint selection, not a refresh delay.

The Services UI requires the Ubuntu adapter integration documented in
[backend/INTEGRATION.md](backend/INTEGRATION.md). No live Ubuntu deployment is claimed.
No server/upstream credentials are embedded. Classera fire requires explicit user
confirmation followed by LocalAuthentication. Service controls remain disabled until
the backend explicitly advertises the individual action and dashboard is verified.
The free SideStore build has no APNs entitlement; local notification testing remains.

Windows cannot compile SwiftUI locally. The existing macOS GitHub Actions workflow
is the compile/test authority and packages an unsigned IPA for SideStore re-signing.
Simulator previews use DEBUG-only fixtures; release builds never bypass app lock.

Download ServerControl-IPA from the successful Actions run, extract the outer ZIP, and import ServerControl.ipa into SideStore. Keep the same Apple account and bundle identity to retain app data. Real-iPhone biometrics and live server commands still require device verification. No actual WhatsApp reports are sent by tests.

Remote APNs is not provisioned by this pipeline. See [Apple supported capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios/).

## V3.1

Compact inline navigation titles and grouped search/status/timestamps remove the
remaining PM2 header space. Home, Docker, Services and Settings receive the same
layout audit; empty notice rows are omitted and resource tiles have no forced minimum
height. PM2 card content opens process details (uptime/restarts when reported), while
Logs and protected quick controls stay available. Successful commands provide haptics.

Native PM2/Docker log pages support bounded stdout/stderr, live polling every five
seconds, pause/resume, search, stream filtering, copy/select text, refresh and jump to
latest. Requests coalesce per target, retain successful snapshots, stop on app lock
and never forward tokens outside the trusted endpoints. Logs need authenticated
allowlisted backend routes; unavailable endpoints show an honest availability message.

**BACKEND AGENT REQUIRED:** See backend/INTEGRATION.md for all Services and logs
request/response contracts, existing source roles to inspect, safety limits and deployment
steps. No live Ubuntu access or upstream deployment is claimed. Production uses no mock
service/log data. Debug test fixtures exist only for simulator visual verification.

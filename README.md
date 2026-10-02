# Server Control V2.1

V2.1 fixes dashboard refresh cancellation appearing as a PM2 connection failure. Home, PM2, Docker, app activation and pull-to-refresh all await one API-owned in-flight request. A disappearing/cancelled view cannot cancel that shared request. URL cancellation (-999) and Swift cancellation preserve the prior connection, error, cached snapshot and timestamp; genuine failures still retain cached data and disable controls. The next pull-to-refresh starts immediately after completion, with no retries or delay.

A native SwiftUI iOS 17 app for the existing Ubuntu Server Control API, built on GitHub's macOS runners and installed using SideStore.

## V2

- Adaptive indigo/teal dashboard, resource cards, server status, and searchable PM2/Docker lists.
- Last successful snapshots survive network failures and are clearly labelled; stale or unauthenticated controls stay disabled.
- Start, Restart and Stop require a confirmation followed by Face ID, Touch ID or the device passcode. No passcode means controls stay locked. Failed or cancelled authentication never sends a command. Commands are never automatically retried.
- The existing token remains in Keychain under the same service/account as V1. Replacement uses a checked Keychain update, not delete-before-save. No token appears in logs, source, screenshots or CI.
- Original server-rack AppIcon asset catalog; the build checks that the icon is compiled into the IPA.
- System/light/dark appearance, refresh, loading/error states and notification preferences.
- Gemini remains a placeholder. No access to Gemini, Meta or Discord credentials.

## Existing API contract

Production base URL remains `https://ubuntu-lts.tail341977.ts.net/server-control`. Tailscale Funnel is unchanged; the iPhone does not need the Tailscale VPN.

| Method | Route | Authentication |
| --- | --- | --- |
| GET | `/api/health` | Public/minimal |
| GET | `/api/dashboard` | Bearer token |
| POST | `/api/process/<id>/<action>` | Bearer token |
| POST | `/api/docker/<name>/<action>` | Bearer token |

Actions remain `start`, `restart`, `stop`. The V1 camelCase Codable models are unchanged. HTTPS is required, requests are not cached, redirects are rejected to avoid credential forwarding, and container names are encoded as single path segments. Ubuntu and Funnel configuration are not changed by V2.

## Notification foundation and limits

This free Apple ID / SideStore build **does not support native APNs delivery**. Apple limits provisioning capabilities by membership, and Push Notifications requires the appropriate supported profile and entitlement. See [Apple's supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios) and [registering with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).

V2 includes typed alert events, category/threshold preferences stored on this iPhone, an unavailable transport adapter, and an explicit local notification permission/test UI. The test is only a local presentation check. Preferences do not activate monitoring or sync to Ubuntu. No APNs registration, `aps-environment` entitlement, background polling, or remote-notification background mode is added.

For notifications while Server Control is closed, the Ubuntu server must detect events and send them through a future transport. Options include an independently provisioned notification app or native APNs after moving to supported paid provisioning. The transport needs separate design and credentials held on Ubuntu. No live backend changes are needed for this V2 release.

## Build and verification

GitHub Actions generates the Xcode project with XcodeGen, builds the unsigned iPhone Release app, runs simulator unit tests for API compatibility and authentication boundaries, validates the compiled icon and Face ID privacy description, and packages `Payload/ServerControl.app` as `ServerControl.ipa` with its SHA-256 checksum.

Optional simulator screenshots can be requested with the Capture optional simulator screenshots switch when manually running the workflow. They use Debug-only fixture data and are separate from the normal build path.

Download `ServerControl-IPA` from the successful Actions run, extract the outer ZIP, and import the IPA into SideStore. Update the existing app using the same Apple account/bundle identity to retain its data. Device biometric prompts, local notification presentation and live server commands still require real-iPhone verification.

Preview fixtures are compiled only in Debug. They cannot send server commands and are excluded from Release. No server tokens, Apple certificates, or provisioning profiles are needed in GitHub.

To regenerate the original icon, run `python3 tools/generate_icon.py` with Pillow installed.

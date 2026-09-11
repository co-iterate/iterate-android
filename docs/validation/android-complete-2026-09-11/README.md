# Android companion integration candidate — 2026-09-11

Status: **not end-to-end accepted; not installed or published**.

This candidate starts from the owner-confirmed UI branch at `45241be`, retaining the four attachment/source actions, fully expanded active projects without search, keyboard insets and light/dark appearance. It transplants connection recovery from `32f2fcb` without restoring the old placeholder UI or separate send socket.

Implemented candidate behavior:

- Native v2 HTTPS/WSS pairing, same-origin and expiry validation, Android identity claim, Keystore-encrypted credential persistence. Enrollment and authenticated HTTP do not follow redirects.
- An application-level connection owner shared by the activity and an optional, user-started remoteMessaging foreground service. Network callbacks resume recovery; socket events determine status. Stop disables continuous mode.
- A native connection screen replacing the unpaired loopback WebView; common authenticated access for project/file actions. Notification permission is requested after pairing/continuous mode activation.
- Background stream messages generate private system notifications. A persistent bounded list suppresses repeat reminders; notification clicks retain their target across reconnection.
- Encrypted pending replies retain an operation ID until the desktop acknowledges receipt. Transport retry uses the same ID. Credentials bind the reply to its original pairing; changing desktop does not forward it elsewhere. An uncertain result requires checking the desktop, with an explicit discard action in connection settings.

Desktop counterpart: `/Users/apple/.codex/worktrees/cunzhi-android-companion-complete-20260911`, based on installed desktop source `370ed422c`. It permits authenticated Android identity and adds `/api/mobile/reply`, device-scoped durable receipts, strict request targeting and direct delivery. A reserved operation left by a crash is uncertain and is never blindly executed again. Receipts contain a payload digest, not reply text. Storage is capped at 1,000 receipts; retention/maintenance still needs a product decision before public release.

## Validation performed

- `:app:testDebugUnitTest`: 26 tests pass (9 recovery, 7 parser, 3 voice, 5 enrollment, 2 authenticated HTTP/reply).
- `:app:assembleDebug`: successful. No release signing or installation claim.
- Desktop reply journal: 3 tests pass in a small Cargo harness importing the actual source module (replay, conflicting payload, interrupted/corrupt receipt). This is **not** a full desktop build or route integration test.
- Source diff whitespace check passes.
- Headless Android 14 emulator start failed explicitly at `hasSufficientDiskSpace`; only approximately 1.4 GB remained. No device/runtime acceptance performed for this candidate.

## Outstanding before claiming completion

1. Restore sufficient build storage (approximately 20 GB free requested); compile and test the full desktop candidate, including native auth, iOS pairing regression and reply-route authorization/deduplication.
2. Independent read-only review when the owner authorizes a reviewer; no subagent has been started.
3. Install and verify the Android candidate in a working emulator/device; test Keystore restart, service Stop/restart, notification permission/click, switch of pairing, and pending reply recovery.
4. Test the real authenticated desktop chain, project/file/image access and reply receipt. Current desktop installation is unchanged and still rejects Android claims.
5. Verify network loss, screen-off/Doze, process reclaim and overnight behavior on the intended physical phone. No physical Android is currently attached.
6. Select/configure the actual system push channel and server integration. JPush/OEM/FCM accounts/configuration are not available in this task. Stream-generated local notifications do not replace provider push when Android stops the app.
7. Relay-only enrollment, public release support matrix, production signing, release/merge/push remain pending.

No private pairing grant, bearer, credentials, production task or account was used in the unit tests. Debug-only loopback parsing is enabled solely for local fixture testing; release pairing requires HTTPS/WSS.

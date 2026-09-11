# Android companion integration candidate — 2026-09-11

Status: **Android 14 emulator fixture accepted; real desktop chain and release pending**.

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
- `:app:assembleDebug` and test APK build: successful. Installed only in a read-only Android 14 emulator overlay; no production signing or physical-phone installation.
- Desktop reply journal: 3 tests pass in a small Cargo harness importing the actual source module (replay, conflicting payload, interrupted/corrupt receipt). This is **not** a full desktop build or route integration test.
- Source diff whitespace check passes.
- Emulator startup initially failed for disk space. After the existing storage guard reclaimed caches, the original AVD booted with a read-only overlay. Ten instrumentation tests pass: eight accepted UI regressions, corrupt pending-record protection, and a real Activity/Keystore/foreground-service/system-notification/reply-retry test against an in-process MockWebServer fixture. Notification acceptance uses a real notification shade click and verifies the exact request is visible. HTTP 503 then success preserves the operation ID. This does not establish live-desktop compatibility, Doze or overnight reliability.
- Fixed unpaired network-loss status and preserved unreadable pending-record presence so startup cannot silently overwrite a damaged reply.

## Outstanding before claiming completion

1. Full desktop CI run 34612907422 passed: 7 native pairing tests, 3 reply journal tests and Apple Silicon executable build. Candidate a21e82862 was downloaded and its hash verified; the local candidate bundle passed Developer ID deep/strict signature and source receipt verification plus a read-only --version loader check. Real reply-route authorization/delivery integration is still pending. The first CI run failed two journal fixtures; atomic unique test-directory suffixes resolved the observed failures in the final run.
2. Independent read-only review when the owner authorizes a reviewer; no subagent has been started.
3. Extend emulator acceptance to full process death/restart, pairing changes and network transitions; fixture coverage currently verifies Keystore reread, service Stop, notification click and same-ID transport retry.
4. Test the real authenticated desktop chain, project/file/image access and reply receipt. Current desktop installation is unchanged and still rejects Android claims.
5. Verify network loss, screen-off/Doze, process reclaim and overnight behavior on the intended physical phone. No physical Android is currently attached.
6. Select/configure the actual system push channel and server integration. JPush/OEM/FCM accounts/configuration are not available in this task. Stream-generated local notifications do not replace provider push when Android stops the app.
7. Relay-only enrollment, public release support matrix, production signing and release/merge remain pending. Only the desktop private candidate has push authorization; the Android candidate remains local.

No private pairing grant, bearer, credentials, production task or account was used in the unit tests. Debug-only loopback parsing is enabled solely for local fixture testing; release pairing requires HTTPS/WSS.

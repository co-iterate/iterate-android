# Android companion integration candidate — 2026-09-11

Status: **Android emulator fixtures and independent review passed; desktop production candidate installed; physical-device acceptance and release pending**.

This candidate starts from the owner-confirmed UI branch at `45241be`, retaining the four attachment/source actions, fully expanded active projects without search, keyboard insets and light/dark appearance. It transplants connection recovery from `32f2fcb` without restoring the old placeholder UI or separate send socket.

Implemented candidate behavior:

- Native v2 HTTPS/WSS pairing, same-origin and expiry validation, Android identity claim, Keystore-encrypted credential persistence. Enrollment and authenticated HTTP do not follow redirects.
- An application-level connection owner shared by the activity and an optional, user-started remoteMessaging foreground service. Network callbacks resume recovery; socket events determine status. Stop disables continuous mode.
- A native connection screen replacing the unpaired loopback WebView; common authenticated access for project/file actions. Notification permission is requested after pairing/continuous mode activation.
- Background stream messages generate private system notifications. A persistent bounded list suppresses repeat reminders; notification clicks retain their target across reconnection.
- Encrypted pending replies retain an operation ID until the desktop acknowledges receipt. Transport retry uses the same ID. Credentials bind the reply to its original pairing; changing desktop does not forward it elsewhere. An uncertain result requires checking the desktop, with an explicit archive action in connection settings. The original ciphertext is atomically retained as a separate draft; text/options/images remain viewable after process death and no draft is automatically forwarded to a new pairing. Permanent draft deletion requires confirmation.

Desktop counterpart: candidate `3678e91ee` on `codex/android-companion-complete-20260911`, based on previously installed desktop source `370ed422c`. It permits authenticated Android identity and adds `/api/mobile/reply`, device-scoped durable receipts, strict request targeting and direct delivery. A reserved operation left by a crash is uncertain and is never blindly executed again. Receipts contain a payload digest, not reply text. Storage is capped at 1,000 receipts; retention/maintenance still needs a product decision before public release.

## Validation performed

- `:app:testDebugUnitTest`: 27 tests pass (9 recovery, 7 parser, 3 voice, 5 enrollment, 3 authenticated HTTP/reply).
- `:app:assembleDebug` and test APK build: successful. Installed only in a read-only Android 14 emulator overlay; no production signing or physical-phone installation.
- Desktop CI run 34616433224 passed full Rust test compilation, 7 native pairing tests, 3 journal tests, conversation-route tests, the Tauri Apple Silicon production build and embedded frontend checks. The installed candidate passed Developer ID signature, source-receipt and UI-readiness verification. Full authenticated mobile reply-route integration remains pending.
- Source diff whitespace check passes.
- Emulator startup initially failed for disk space. After the existing storage guard reclaimed caches, the original AVD booted with a read-only overlay. Fourteen instrumentation test invocations pass: eight accepted UI regressions, corrupt pending-record protection, and a real Activity/Keystore/foreground-service/system-notification/reply-retry test against an in-process MockWebServer fixture. Notification acceptance uses a real notification shade click and verifies the exact request is visible. HTTP 503, 408 and 429 then success preserves one operation ID and the same WebSocket. Four additional cases validate staging a reply, an explicit adb force-stop with no remaining PID followed by cold-start archive/preview, preservation of damaged ciphertext, and keeping pending data when the 10-draft limit is reached. This does not establish live-desktop compatibility, Doze or overnight reliability.
- Fixed unpaired network-loss status and preserved unreadable pending-record presence so startup cannot silently overwrite a damaged reply.

## Remaining acceptance and release work

1. Test the real authenticated desktop chain, project/file/image access and reply receipt. The compatible desktop candidate is installed, and its formal public endpoint health and identity checks pass. Unauthenticated pairing-status and reply calls return 401. No physical Android is attached.
2. Verify network transitions, screen-off/Doze, process reclaim and overnight behavior on the intended phone. Fixture process-stop recovery passed, but this does not establish physical-device reliability.
3. Select/configure the actual system push channel and server integration. JPush/OEM/FCM configuration is not available in this task. Stream-generated local notifications do not replace provider push when Android stops the app.
4. Relay-only enrollment, public release support matrix, production signing and release/merge remain pending. The owner has authorized pushing these candidate branches; this is not a published release.

## Opt-in live endpoint acceptance

`RealDesktopConnectionTest.probeConfiguredHttpsEndpoint` passed once from the emulator against the explicitly selected HTTPS desktop endpoint. This validates public version access only, not authenticated pairing or reply delivery. Supply the `desktop_base_url` instrumentation argument to select an endpoint; the test is skipped without it.

`pairThroughTheOwnersFreshOffer` is an opt-in helper and has not been accepted against the live desktop. It requires a fresh owner-issued pairing offer in the app's external-files `owner-pairing-offer.txt`, consumes and deletes that file, and deliberately leaves the emulator paired with continuous mode enabled for follow-up acceptance. It emits only connection status and device identity, never bearer/grant data. Run it only on a disposable acceptance device; disconnect/forget the device after the session. It is skipped when no offer file exists.

No private pairing grant, bearer, credentials, production task or account was used in the unit tests. Debug-only loopback parsing is enabled solely for local fixture testing; release pairing requires HTTPS/WSS.

## Independent review and packaging correction

Astra High independent read-only review identified missing timeline routing, cold-start discard data loss, and permanent rejection of HTTP 408/429. All three were fixed; source re-review found no new install blockers. Root validation passed the 27 JVM and 14 instrumentation invocations above. Desktop timeline recording now reuses the existing stable route resolver.

The earlier plain Cargo release artifact passed compilation/signature checks but failed the actual production frontend check and was rejected before installation. Private CI run 34616433224 uses the existing release workflow’s pinned Tauri CLI and enforces production mode plus embedded frontend checks. That run succeeded. The production candidate was installed with a verified rollback backup; production mode, embedded assets, code signature, source receipt and GUI readiness passed. Live authenticated Android acceptance remains pending.

# Android persistent connection and background messaging plan

Date: 2026-09-11. Status: proposed implementation plan; production code unchanged.

## Outcome

Let users continue an iterate conversation across foreground use, background use,
screen lock and network interruptions. Cover mainstream Android distributions
through available system push channels, with explicit reduced capability on
devices that have neither usable Google services nor a supported OEM channel.

This plan extends the existing [Windows-to-Android Relay plan](windows-android-relay-connection-plan.md).
It preserves its authenticated public Relay architecture. A loopback emulator
fixture is a development test, not an alternative production connection route.

Do not promise an uninterruptible application socket or immediate notifications
on every Android device. Notification permission, user force-stop, Doze, network
availability, provider eligibility and OEM behavior remain meaningful boundaries.

## Verified source baseline

Baseline: public `main` at `94deae14155c2e5b2178d5bcbdfc1293cde55026`.

| Existing component | Observed behavior | Gap |
| --- | --- | --- |
| `mobile/BridgeClient.kt` | Opens an OkHttp WebSocket and parses request frames | Defaults to phone loopback; no paired credentials, client ping interval or reconnect loop |
| `mobile/BridgeViewModel.kt` | Retries version HTTP request and collects one socket flow | HTTP success is treated as connected; socket failure does not recreate the flow |
| `PairingActivity.kt` / `MainActivity.kt` | Forwards a pairing payload extra | Main activity does not consume it to establish an authenticated connection |
| `AndroidManifest.xml` | Internet and microphone permissions, activities | No foreground service or notification permission declaration |
| `BridgeClient.sendAction` | Opens a separate socket, queues an action, closes | Queue acceptance is not a business processing acknowledgement |
| Build configuration | minSdk 24, target/compile SDK 36 | API 34 emulator alone cannot validate target-36 behavior changes |

Paths above are relative to `app/src/main/java/com/kexin94yyds/iterate`, except
the manifest and build configuration. Baseline limits are not newly implemented
features. Changes on other branches are outside this plan's baseline.

## Architecture

```text
Desktop connector -> authenticated Relay -> durable pending event
                                         |-> active Android stream
                                         |-> notification dispatcher
                                               -> OEM / FCM system channel

Android notification click -> authenticate -> fetch current task -> reply
Android reconnect          -> resume cursor / current pending snapshot
```

The application uses one connection owner. UI subscribes to state; an optional,
user-started foreground service owns the active-session lifetime. System push
provides a separate user-visible reminder path when the application stream is
unavailable. Push receipt does not imply background application code executed.

## Implementation sequence

### Phase 0 — establish reproducible baseline evidence

- Run `:app:testDebugUnitTest` and `:app:assembleDebug` on the pinned baseline.
- Launch the existing Android emulator using a temporary snapshot overlay.
- If the current client can run, use `adb reverse` to connect its fixed loopback
  port to an isolated synthetic Bridge fixture. Do not expose private desktop
  sessions or weaken the real Bridge authentication.
- Observe handshake, request rendering, server Ping/Pong while foreground and
  while backgrounded, and behavior after a controlled connection close.
- Record emulator API, app commit, observation duration and fixture boundary.
- Do not call this authenticated Relay, OEM push or overnight device acceptance.

### Phase 1 — authenticated pairing and truthful connection state

Files: `PairingActivity.kt`, `MainActivity.kt`, `mobile/BridgeClient.kt`,
`mobile/BridgeViewModel.kt`; proposed `mobile/PairingRepository.kt`,
`mobile/DeviceCredentialStore.kt`.

- Validate enrollment schema, endpoint and expiry; claim the Android identity
  using the public Relay contract from the existing connection plan.
- Store credentials with Android Keystore-backed protection. Do not print
  enrollment grants or credentials in diagnostics.
- Derive HTTP and WSS endpoints from the approved pairing, not hard-coded
  loopback. Keep development forwarding out of the production path.
- Expose unpaired, connecting, online, waiting-network, retrying and revoked
  states. A version endpoint response is not proof of a live stream.
- Validate expired/replayed grants, revoke, restart persistence and two-user
  isolation before real-account testing.

### Phase 2 — recoverable active connection

Files: `mobile/BridgeClient.kt`, `mobile/BridgeViewModel.kt`; proposed
`mobile/ConnectionManager.kt`, `mobile/ConnectionService.kt`; manifest.

- A single serialized owner coordinates connect, close and reconnect.
- Negotiate heartbeat behavior with Relay; use a bounded Pong timeout and
  randomized exponential backoff. Cancel stale callbacks using connection
  generations. Wait for usable network rather than retrying continuously offline.
- Retry transient transport failures; terminate or require user action for
  revoke, unsupported protocol and unrecoverable authentication failures.
- Provide a user-started continuous-session mode with an informative foreground
  service notification and a Stop action. Do not restart after deliberate Stop.
- Evaluate `remoteMessaging` against the actual cross-device messaging purpose;
  do not treat it as a generic keepalive exemption. Do not implement all-day
  operation using `dataSync`, whose target-35+ background runtime is limited.
- Test protocol recovery with a fixture before connecting production accounts.

### Phase 3 — system notifications across device families

Files: manifest, `app/build.gradle.kts`; proposed `mobile/push/PushRegistration.kt`,
`mobile/push/PushRouter.kt`, `mobile/notifications/TaskNotifications.kt`.
Server work belongs to the Relay implementation repository, not this Android seed.

- Prototype one aggregator, initially JPush; compare Getui if eligibility,
  supported channels or operational constraints make it preferable. No vendor
  purchase or final selection is implied by this plan.
- Register channels by actual SDK capability and successful token acquisition,
  not only manufacturer name. Cover available Xiaomi, Huawei, Honor, OPPO, vivo,
  Meizu and FCM routes. Verify OnePlus/realme/iQOO variants individually.
- Choose a single primary push route per device/event. Avoid duplicate direct
  FCM and aggregator-FCM sends without an intentional arbitration policy.
- Handle notification permission, channel settings, token rotation, logout and
  revocation. Bind registration to the authenticated user and paired device.
- Send a minimal user-facing reminder and opaque event ID. Fetch full content
  after authentication; an event ID must not itself grant access.
- Use high priority only for eligible user-visible events. Map real task events
  to approved vendor categories/templates; do not assume an unlimited category.
- Model no-system-channel devices as limited support. Optional UnifiedPush can
  serve users willing to install/configure a distributor, but is not a universal
  zero-setup fallback.

### Phase 4 — durable task and reply semantics

Files: parser/models/client; proposed `mobile/MessageRepository.kt`,
`mobile/PendingReplyStore.kt`, related focused tests. Relay needs matching APIs
and persistence before this phase can pass end-to-end acceptance.

- Use stable event/operation IDs, bounded replay cursors and authoritative task
  status. Define retention, expiry and snapshot recovery after cursor expiry.
- Keep a reply pending until business acknowledgement; retry the same operation
  ID after an uncertain delivery. The server returns the prior result rather
  than executing twice.
- Coordinate notification and stream delivery. Client in-memory deduplication
  alone cannot stop duplicate notifications displayed directly by an OEM service;
  use server routing and supported notification replacement identifiers too.
- Track provider acceptance, device receipt, display, click and business completion
  separately. Missing display telemetry is unknown, not successful display.
- Store push sending credentials only in controlled server infrastructure, never
  in the APK or as a shared global secret on every customer desktop.

### Phase 5 — staged compatibility acceptance

- Validate current supported Google/AOSP versions including API 35/36 behavior,
  plus one or more real devices for every OEM family promised at release.
- Exercise foreground, background, overnight screen-off, forced Doze, low battery,
  Wi-Fi/cellular transitions, offline recovery, process reclaim and user force-stop
  as separate cases.
- Test production-signed builds and approved production push channels, not just
  provider test devices or simulator registration.
- Measure sample count, p50/p95 delay, recovery duration, duplicate actions,
  missing pending tasks and battery consumption against a standby baseline.
- Publish a verified compatibility matrix. Do not infer universal reliability or
  a delivery-rate percentage from one emulator or provider marketing claims.

## Dependencies and decisions

Prerequisites for public background reminders include per-provider account and
app eligibility, signing identity, notification categories and available Relay
persistence. Aggregation does not waive OEM enrollment or store requirements.

Before production implementation, settle: provider commercial terms, applicable
OEM qualifications, actual message category, retention/expiry policy and the
supported OS/device release matrix. The current minSdk 24 is a source fact, not
proof that every Android 7+ device can use the final provider SDK combination.

The existing Relay plan's domain and isolation decisions remain authoritative.
No new per-customer tunnel or shared desktop credential is introduced here.

## Verification and rollback

- Baseline: repository unit tests and debug build; isolated fixture emulator run.
- Protocol: negative authentication, stale callbacks, network loss, replay and
  duplicate processing tests; fake time where appropriate for retry behavior.
- Runtime: real-device foreground service and notification matrix above.
- Ship pairing, connection recovery, push and persistence in separate reviewed
  changes. Gate new push registration/routing and continuous mode behind explicit
  capabilities so rollback can retain existing foreground interaction.
- Rollback must preserve pending replies and device identity; do not solve an
  incident by discarding unacknowledged operations or reviving revoked credentials.

## Official references (checked 2026-09-11)

- [Android Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Android 15 service limits](https://developer.android.com/about/versions/15/behavior-changes-15)
- [Android stopped state](https://developer.android.com/about/versions/15/behavior-changes-all)
- [Notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission)
- [FCM device prerequisites](https://firebase.google.com/docs/cloud-messaging/android/get-started)
- [FCM message priority](https://firebase.google.com/docs/cloud-messaging/android-message-priority)
- [JPush OEM integration](https://docs.jiguang.cn/jpush/client/Android/android_3rd_guide)
- [Getui channel semantics](https://docs.getui.com/getui/dos/third_party/)
- [Xiaomi enrollment](https://dev.mi.com/xiaomihyperos/ability/mipush)
- [Xiaomi 2026 message categories](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2322)
- [Honor notification versus data messages](https://developer.honor.com/cn/kitdoc?category=ai&docId=introduction.md&kitId=11002&navigation=guides)
- [UnifiedPush distributor model](https://unifiedpush.org/news/20221218_unifiedpush/)

Provider requirements are time-sensitive. The references establish constraints;
they do not certify this application's eligibility or measured delivery quality.

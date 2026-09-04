# Windows-to-Android Relay Connection Plan

- Status: implementation plan; no production code changed
- Audience: Android, Windows desktop, Relay, and release contributors
- Product domain: `iterate.xin`
- Target Relay endpoint: `https://relay.iterate.xin` / `wss://relay.iterate.xin`
- Related Android work: [Issue #1 — authenticated pairing and request loop](https://github.com/co-iterate/iterate-android/issues/1)
- Related UI reference correction: [PR #4 — verified Build 19 UI reference](https://github.com/co-iterate/iterate-android/pull/4)

## Outcome

Let an ordinary user install iterate on Windows and Android, scan one QR code,
and reach only that Windows computer without buying a domain, configuring
Cloudflare, installing Tailscale, or opening an inbound router port.

The product route is:

```text
Android companion
  ⇅ authenticated HTTPS/WSS
relay.iterate.xin
  ⇅ authenticated outbound WSS
Windows iterate connector
  ⇅ loopback HTTP/WS
127.0.0.1:8080 Bridge
```

Port `8080` is local to each computer. Alice and Bob can both use
`127.0.0.1:8080` because the addresses refer to different machines. Relay
routes traffic by authenticated connector identity; it does not assign a
different local port to every customer.

## Decisions frozen by this plan

1. **One public Relay endpoint.** V1 uses `relay.iterate.xin`; it does not create
   a DNS record, subdomain, or Cloudflare Tunnel for every user.
2. **No customer networking setup.** Customer Windows machines do not receive
   the iterate Cloudflare API token and do not need `cloudflared` for the normal
   path.
3. **Local Bridge stays local.** The Windows connector reaches its own Bridge at
   `127.0.0.1:8080`. Relay never exposes arbitrary customer ports.
4. **Identity, not hostname, selects the computer.** A non-guessable
   `connector_id` and scoped credentials define routing. A hostname is not an
   authorization mechanism.
5. **QR codes contain only short-lived enrollment material.** They never contain
   connector long-term credentials, Relay administrator tokens, activation
   codes, model credentials, or Cloudflare credentials.
6. **Quick Tunnel is optional development fallback only.** A random
   `trycloudflare.com` route may support a future temporary trial, but it is not
   the public long-term architecture.
7. **Relay is a broker, not a remote runtime.** Models, MCP credentials, local
   files, and tool execution remain on the user's Windows computer.

## Cloudflare boundary

- Cloudflare Tunnel and proxied WebSockets are available on all plans, but this
  does not make Relay hosting, storage, monitoring, or support cost-free.
- A single `relay.iterate.xin` route avoids per-user DNS and Tunnel allocation.
- Cloudflare currently documents default limits of 1,000 tunnels and 1,000
  Tunnel/Mesh routes per account. This is another reason not to create one
  Named Tunnel per customer.
- Quick Tunnels generate free random `trycloudflare.com` names, but Cloudflare
  explicitly limits them to development and testing.

References:

- [Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/)
- [Cloudflare WebSockets](https://developers.cloudflare.com/network/websockets/)
- [Cloudflare One account limits](https://developers.cloudflare.com/cloudflare-one/account-limits/)
- [Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)

## Why the current owner setup does not generalize

The existing owner-verified phone setup uses a Named Tunnel that reaches one
specific desktop Bridge. That proves the pairing, authenticated WebSocket, and
mobile response concepts, but the hostname still points to that one computer.
Giving the same QR or hostname to another user would connect them to the wrong
desktop.

Public users instead need a central Relay. Every Windows connector opens an
outbound connection to Relay, and Relay maps each mobile device to its approved
connector.

## Current completion ledger

| Capability | Current evidence | Status |
| --- | --- | --- |
| Local desktop Bridge on port 8080 | Existing desktop implementation and owner-device use | Proven for the owner path |
| One-time mobile pairing and scoped credentials | Existing desktop/iOS behavior and local Relay MVP | Proven locally, not public multi-tenant |
| Relay device status, stream, commands, revoke, and audit | Existing Rust Relay MVP and local enrollment smoke | Implemented as a local prototype |
| Relay persistence | Core device, command, pairing, and mobile credential state is memory-backed | Missing |
| Public production Relay | A target `relay.iterate.xin` deployment has not been established | Missing |
| Windows connector core loop | Outbound WebSocket, heartbeat, reconnect, and Bridge forwarding exist | Partial |
| Windows service lifecycle | Existing service control uses macOS LaunchAgent concepts | Missing |
| Android deep-link entry | `PairingActivity` forwards the payload to `MainActivity` | Partial |
| Android secure pairing | Payload validation, claim, Keystore, Relay stream, and recovery are absent | Missing |
| Android foreground request loop | Compose seed exists but still defaults to phone-local loopback | Missing for a real desktop |
| Android background notification | Provider and token lifecycle are undecided | Missing |
| Two-user isolation evidence | No Windows A/B plus Android A/B production-equivalent run | Missing |

This is not “half of a finished product.” The protocol and local prototype are
substantial, but the public multi-user, Windows lifecycle, Android client, and
deployment gates remain open.

## Target identities and data

Relay needs persistent records for:

- `users`: product owner of connectors and mobile devices;
- `connectors`: one Windows installation, token hash, capabilities, status, and
  last-seen time;
- `mobile_devices`: Android device, token hash, scopes, push metadata, and
  revoke state;
- `pairing_grants`: connector-bound, short-lived, single-use claims;
- `connector_snapshots`: bounded current state needed after mobile reconnect;
- `commands`: connector-bound action, nonce, deadline, result, and terminal
  state;
- `audit_events`: redacted security and lifecycle evidence.

Long-lived raw credentials are returned once and stored only in platform secure
storage. Relay persists hashes, prefixes suitable for user-facing identification,
timestamps, scopes, and revocation state.

## Protocol flow

### 1. Windows connector enrollment

1. Windows iterate starts and verifies that its local Bridge is healthy on
   `127.0.0.1:8080`.
2. The user completes the selected product entitlement step. Whether V1 uses a
   desktop activation code or an account is a product-owner decision; Relay must
   still create an internal user boundary.
3. Relay creates a unique connector and returns its long-lived connector
   credential once.
4. Windows stores the credential with Windows Credential Manager or DPAPI, not
   in command arguments, logs, a repository file, or a plain-text shared config.
5. The connector exchanges the long credential for a short-lived access token
   and opens an outbound WebSocket to Relay.
6. It sends a connector hello, version, capabilities, and periodic heartbeat.
   Relay marks it offline after the documented heartbeat window.

### 2. Desktop-generated mobile pairing

1. The user selects **Connect phone** in Windows iterate.
2. Desktop asks Relay for a pairing grant bound to the current connector.
3. Relay returns a short-lived, single-use token and expiry.
4. Desktop renders a QR payload containing only:
   - schema version;
   - Relay HTTPS/WSS origin;
   - connector ID;
   - pairing grant;
   - issued and expiry timestamps;
   - non-sensitive capability metadata.
5. Desktop shows pending, claimed, connected, expired, and cancelled as separate
   states. A claim alone is not displayed as a live mobile connection.

### 3. Android claim and secure storage

1. Android receives the QR through `iterate://pairing` initially; a verified
   HTTPS App Link is required before public release.
2. It bounds payload size, validates schema and timestamps, permits only the
   approved Relay origin, and rejects malformed or expired material before any
   network request.
3. Android claims the grant against Relay with a stable generated device ID and
   device label.
4. Relay consumes the grant atomically and returns a connector-bound mobile
   credential with minimum scopes.
5. Android stores the credential in Android Keystore-backed storage.
6. Android opens the connector-specific authenticated Relay stream and requests
   an authoritative state snapshot.

### 4. Request and response routing

1. Windows Bridge publishes a pending request to its connector.
2. Connector forwards an allowlisted envelope to Relay.
3. Relay validates connector identity, persists only the minimum bounded
   snapshot, and publishes it to mobile streams bound to that connector.
4. Android renders the request and sends an action containing the exact
   invocation ID, state revision, nonce, and intended action.
5. Relay checks mobile scope and connector binding, then forwards the action to
   the correct Windows connector.
6. Windows hands the action to its local Bridge. The authoritative result returns
   along the same identity chain.
7. Android clears the request only after an accepted or idempotent terminal ACK.

### 5. Offline and background behavior

- WebSocket presence, paired status, and background-notifiable status are
  separate.
- Relay retains only a bounded current snapshot and command ledger needed for
  reconnect; it does not become a second conversation database by accident.
- When Windows is offline, Android shows offline and cannot queue arbitrary tool
  actions indefinitely.
- Android background delivery requires a separate push decision. FCM is a
  likely global default, but China-distribution requirements may require an OEM
  push strategy or an explicit foreground-only first release.
- Push payloads contain minimal routing metadata and no full prompt, credential,
  or tool output. Android pulls authoritative state after opening.

## Workstreams

### A. Relay service

Required:

- deploy `relay.iterate.xin` behind HTTPS/WSS;
- replace process-memory identity state with a persistent database;
- implement users, connector enrollment, mobile claims, expiry, rotation, and
  revocation;
- guarantee tenant isolation on every status, stream, snapshot, and command
  query;
- add bounded payloads, nonce/replay protection, rate limits, and redacted audit;
- define backup, restore, migration, health, metrics, and rollback procedures;
- decide whether request envelopes must be end-to-end encrypted so Relay sees
  ciphertext rather than prompt contents.

### B. Windows desktop

Required:

- keep the Bridge local on `127.0.0.1:8080`;
- add connector enrollment and secure credential storage;
- replace macOS-specific LaunchAgent control with a Windows Service lifecycle;
- recover across reboot, sleep/wake, network changes, crash, app upgrade, and
  credential rotation;
- show local Bridge, Relay enrollment, connector online, phone paired, and
  background-notifiable as distinct states;
- make service install, repair, rollback, and uninstall explicit and auditable.

### C. Android companion

Expected production files to change include:

- `app/src/main/AndroidManifest.xml` — verified pairing entry and network policy;
- `app/src/main/java/com/kexin94yyds/iterate/PairingActivity.kt` — bounded handoff;
- `app/src/main/java/com/kexin94yyds/iterate/MainActivity.kt` — cold/warm pairing delivery;
- `app/src/main/java/com/kexin94yyds/iterate/mobile/BridgeClient.kt` — selected authenticated endpoint instead of loopback;
- `app/src/main/java/com/kexin94yyds/iterate/mobile/BridgeViewModel.kt` — pairing and recovery state machine;
- `app/src/main/java/com/kexin94yyds/iterate/mobile/WorkbenchModels.kt` — connector, invocation, and ACK identities;
- `app/src/main/java/com/kexin94yyds/iterate/mobile/MobileWebViewScreen.kt` — authenticated selected Relay/Bridge origin.

Likely focused additions are a pairing contract decoder, a Keystore-backed
credential store, a Relay stream client, and explicit connection-state models.
Names may change during implementation; responsibilities must remain separated.

### D. Domain and operations

Required before public use:

- confirm `iterate.xin` is active in the intended Cloudflare account;
- create `relay.iterate.xin` only after the Relay deployment target is chosen;
- keep Cloudflare account/API credentials server-side;
- choose hosting region, database, backup retention, log retention, alerting, and
  a monthly cost ceiling;
- prepare incident response for leaked connector/mobile credentials;
- publish privacy and deletion behavior for Relay-held metadata.

## First-half milestone: foreground connection MVP

This milestone proves the product route without claiming release readiness.

Deliverables:

1. A staging Relay with persistent connector/mobile identity and one stable
   HTTPS/WSS hostname.
2. A Windows foreground connector that enrolls securely and forwards only to its
   local 8080 Bridge.
3. Android QR validation, Relay claim, secure credential storage, authenticated
   stream, state sync, and one exact response path.
4. Two Windows connectors and two Android devices demonstrating strict A/B
   isolation.
5. Relay restart recovery and credential revoke behavior.

Deferred from this milestone:

- Windows Service installation and polished repair UI;
- background push and notification routing;
- full account/team management;
- end-user billing;
- store release and large-scale operations.

The first-half milestone passes only if the foreground connection works through
Relay with no user Cloudflare/domain setup and no unauthenticated access. It
must be labelled an internal or beta connection MVP.

## Second-half milestone: public product readiness

Required after the foreground MVP:

1. Windows Service, Credential Manager/DPAPI, update, repair, rollback, and
   uninstall lifecycle.
2. Android background strategy, push token lifecycle, notification privacy, and
   foreground resync.
3. Connector/mobile credential expiry, rotation, revoke UI, and lost-device
   recovery.
4. Database migrations, backups, restore drills, rate limiting, metrics, alerts,
   and abuse controls.
5. Verified HTTPS App Links, Windows signing, Android signing, distribution,
   privacy copy, and support runbook.
6. Real-device evidence for Windows restart, Relay restart, mobile lock,
   Wi-Fi/cellular change, stale invocation, duplicate tap, revoke, and two-user
   isolation.

## Preparation checklist

### Product-owner decisions

- [ ] V1 entitlement: desktop activation code or user account.
- [ ] Relay content boundary: metadata/minimal snapshots or end-to-end encrypted
  envelopes.
- [ ] Initial market: global FCM-capable Android, China Android, or foreground-only
  beta.
- [ ] Hosting region, monthly budget ceiling, retention, and deletion promise.
- [ ] Whether Quick Tunnel trial belongs in the first release or a later fallback.

### Infrastructure

- [ ] Relay hosting target and rollback target.
- [ ] Persistent database and backup location.
- [ ] `relay.iterate.xin` DNS/TLS plan.
- [ ] Server-side secret storage and rotation process.
- [ ] Android push project/provider if background delivery is in scope.
- [ ] Monitoring, alerting, rate limiting, and incident response.

### Platform delivery

- [ ] Windows signing certificate and installer/service privileges.
- [ ] Windows Credential Manager/DPAPI storage contract.
- [ ] Android application ID, signing key, verified App Link, and distribution
  channel.
- [ ] At least two isolated Windows and Android device pairs for acceptance.

## Acceptance matrix

| Scenario | Required result |
| --- | --- |
| Two PCs both use local 8080 | No conflict; Relay routes by connector identity |
| Android A uses connector A grant | A connects; Android B and connector B cannot reuse it |
| Pairing grant replay | Same terminal result or explicit rejection; no second device credential |
| Invalid/expired grant | Fail closed with actionable UI |
| Windows offline | Android shows offline; no action is reported as delivered |
| Windows reconnect | Same connector resumes without a new QR |
| Relay restart | Persistent identity and bounded state recover without cross-user leakage |
| Mobile credential revoke | Existing stream closes and future requests fail |
| Duplicate action | Original invocation completes no more than once |
| Relay or mobile sees untrusted payload | Size, type, scope, identity, and revision checks reject it |
| Background notification | Minimal notification leads to authenticated state pull; no prompt content leaks |

No test scripts are added by this planning change. Implementation pull requests
must attach proportionate automated and physical-device evidence without putting
real credentials, QR payloads, or private logs in the repository.

## Decision-quality gate

### Options audited

| Option | Decision |
| --- | --- |
| One Named Tunnel per user | Reject for the public default: operationally heavy and quota-bound |
| Quick Tunnel per user | Keep only as a reversible development/trial experiment |
| One central Relay endpoint | Proceed as the public product architecture |
| Do nothing and retain the owner tunnel | Reject for public claims; it reaches only one desktop |

### Pre-mortem

| Likely failure | Earliest signal | Containment |
| --- | --- | --- |
| Cross-user routing | Connector/device mismatch in audit | Deny before forwarding; stop rollout |
| Relay restart loses pairings | Devices all become unknown after restart | Persistence/restore gate before external beta |
| Windows service leaks token | Credential appears in argv, config, or log scan | Stop release; rotate and move to OS secure storage |
| Android still uses loopback | Network trace targets `127.0.0.1` on phone | Block release build and endpoint fallback |
| Background push is unreliable | Lock-state delivery misses agreed threshold | Ship foreground beta or revise provider strategy |
| Relay becomes a sensitive content store | Prompt bodies appear in retained logs/database | Minimize or encrypt envelopes; shorten retention |

### Verdict

**PROCEED with the foreground Relay MVP; DEFER public release.**

The architecture is supported by existing local protocol evidence and is more
scalable than per-user tunnels. Public release remains blocked until persistent
multi-tenant Relay state, Windows lifecycle, Android secure pairing, credential
revocation, and two-user isolation are independently demonstrated.

## Rollback and stop conditions

- DNS or deployment changes require separate authorization and a documented
  previous target; this plan authorizes neither.
- Stop the pilot immediately on any cross-user access, unauthenticated stream,
  reusable pairing grant, secret in QR/logs, or action delivered to the wrong
  invocation.
- If Relay cannot meet the agreed availability/cost ceiling, keep the current
  owner tunnel and Quick Tunnel as internal tools while revising the public
  architecture. Do not silently downgrade security or claim long-term support.

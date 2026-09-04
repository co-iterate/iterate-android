# iOS-to-Android UI Parity Plan

- Status: implementation handoff
- Audience: Android contributors
- Related work: [Issue #1 — authenticated pairing and request loop](https://github.com/co-iterate/iterate-android/issues/1)
- Android baseline inspected: `67902ff17ee16ad7e1adc0364b320c67e4f9d4e8`
- iOS behavior snapshot inspected: 2026-09-04
- iOS personal-development UI source: `17efc534a4a62dd779a4af8f92051e3b48d26a09`
- Physical-device verification derivative: `873ce7fce840c278ba7d2829b4c4bfaadc8a874e` (the five reference files are unchanged)
- Reference source snapshot: [`docs/reference/ios-ui/`](reference/ios-ui/README.md)

## Outcome

Rebuild the current iterate iOS companion experience in native Jetpack Compose so an Android user sees the same information, can perform the same actions, and receives the same state feedback. Use Android-native controls and accessibility semantics; do not attempt a literal SwiftUI pixel clone.

The implementation boundary is now explicit:

- The request/conversation workbench is native Compose.
- The Home/overview content may remain a WebView because the current iOS app also loads the Bridge mobile page for that route, with a small allowlisted native bridge for prompt, speech-memory, training, ghost-settings, and Home requests.
- Project selection, settings, secure pairing, image preview, timeline, quota inspection, and live-goal status are native Android surfaces.
- Historical `NativeMainPageView` and onboarding HTML prototypes are not design sources for this work.
- This document is self-contained. Android contributors do not need access to the private iOS source tree.

The original snapshot merged in pull request #3 came from the wrong iOS working tree. It is superseded by the committed Build 19 snapshot linked above. Do not use the removed hashes, the former 1,804-line `ContentView.swift`, or branch recency as product evidence.

## Why this plan exists

The repository currently contains a useful Compose seed, but it represents an older mock rather than the current iOS product:

- `MessageCard` includes hard-coded notarization example text that is unrelated to the incoming request.
- The header exposes a New Chat action, while the current iOS header exposes Settings and prevent-sleep controls.
- The footer uses an infinity glyph for a `goal` action, while iOS presents explicit **Continue** and **Confirm** actions.
- The theme toggle changes state, but the rendered theme remains a fixed light palette.
- Markdown, authenticated images, attachments, file mentions, prompt templates, conditional context, project switching, the conversation timeline, ghost completion, usage quota, and live-goal state are missing.
- Connection state is reduced to connecting/connected/offline and does not model sent, reconnecting, rejection, or stale-state recovery.
- Pairing payload forwarding, authenticated endpoint selection, and exact-once action acknowledgement remain incomplete; those protocol requirements are owned by Issue #1.

Do not polish the existing mock in place and call it parity. Replace fixture-only content with real state and implement the surfaces below in order.

## Product and architecture decisions

1. **Compose-first workbench.** Keep the active request, composer, options, timeline, project picker, settings, and pairing UI native.
2. **WebView-only Home route.** The WebView must use the authenticated paired Bridge origin, not `127.0.0.1`, and must carry the same scoped device authorization as other Bridge requests.
3. **Behavior parity before decorative parity.** State, action identity, content, disabled/loading behavior, and recovery are acceptance requirements. Exact SF Symbol shapes are not.
4. **Android-native adaptation.** Respect edge-to-edge insets, system back, IME resize, Material semantics, TalkBack, font scaling, and at least 48 dp interactive targets. A 32 dp visual icon may sit inside a 48 dp target.
5. **One source of truth.** `WorkbenchUiState` (or a replacement immutable state model) drives every visible surface. Composables do not own duplicate Bridge state.
6. **No private implementation import.** Recreate the documented behavior; do not copy the private monorepo, credentials, signing material, relay configuration, or release infrastructure.
7. **Port visible contracts, not Swift helper internals.** The corrected snapshot includes speech-learning stores, route recovery, relay/watch coordination, and allowlisted WebView adapters because they affect the UI. Android should model the visible state and approved protocol contracts, not mechanically translate these helpers.

## Screen hierarchy

```text
System status bar / safe inset
┌──────────────────────────────────────────────────────────┐
│ ∞  Project                                               │
│    Host · task · deadline     Home  Awake  Bell  Theme   │
│                               Settings  ● Connection     │
├──────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────┐ │
│ │ Markdown request, code, links, authenticated images │ │
│ │ ──────────────────────────────────────────────────── │ │
│ │ Upload image · @File · Copy source · Quote source   │ │
│ └──────────────────────────────────────────────────────┘ │
│                                                          │
│ Image attachment previews                                │
│ Reply editor                                              │
│                         Voice button                      │
│ PREDEFINED OPTIONS                                        │
│ [full-width selectable row]                              │
│ QUICK TEMPLATES                                           │
│ [horizontal reorderable chips]                           │
│ CONTEXT APPEND                                            │
│ [active checkbox] [label]                     [switch]   │
│                                                   ┌────┐ │
│                                                   │••••│ │
│                                                   └────┘ │
├──────────────────────────────────────────────────────────┤
│                 Continue        Confirm                  │
└──────────────────────────────────────────────────────────┘
```

On narrow devices the header may wrap or move secondary actions into an overflow menu. The project identity and connection state must remain visible without horizontal scrolling.

## Surface contract

| Surface | Required content and behavior | Android adaptation |
| --- | --- | --- |
| Workbench header | Infinity mark; current project; MCP host, task, and deadline summary; Home/conversation toggle; prevent-sleep; notifications; light/dark mode; settings; colored connection state. Tapping the project opens the project picker. Tapping connection may request a reconnect/restart only when supported. | Keep the icon visuals compact but expose 48 dp targets, labels, selected states, and overflow on narrow widths. Do not restore the old New Chat control unless a separate product requirement is approved. |
| Empty state | “No pending MCP request” plus an explicit resync action. Unpaired, offline, and authenticated-but-idle are distinct states with distinct next actions. | Use one workbench shell rather than a historical onboarding screen. Pairing can open Settings or consume a deep link. |
| Request card | Render the incoming message as Markdown; support selectable text, code blocks, links, and authenticated remote images. A tapped image opens a full-screen zoom/pan preview. Below the message, show Upload image, @File, Copy source, and Quote source. | Remove all hard-coded notarization lines and browser-response fixtures. Use the exact request payload only. |
| Reply composer | Multiline editor, server-provided placeholder, pasted or picked image previews with removal, and voice transcript insertion. Preserve draft while offline or while another non-terminal status arrives. | Handle IME insets and back-to-dismiss-keyboard before navigating away. Use Android photo/document pickers and URI grants rather than filesystem paths supplied by another app. |
| Voice input | Idle, listening, permission denied, and error states. A transcript is inserted into the editor and is never sent without explicit Confirm/Continue action. | Follow runtime permission guidance, show a textual state in addition to color, and provide retry/settings recovery. |
| Predefined options | Display in server order as full-width selectable rows; allow the same selection cardinality supplied by the request contract; include selections in the action payload. | Do not replace the rows with cramped chips merely to reuse the seed component. |
| Quick templates | Horizontal chips populated by synchronized normal prompts. Tapping fills the editor. Reordering is long-press drag and persists through the Bridge only after order changes. | Expose reorder semantics and haptic feedback where available. |
| Context append | Each conditional prompt has a separate active checkbox and true/false switch. Active items append the selected template to the outgoing response. | Do not merge “active” and boolean value into one switch; they are different state. |
| Timeline rail | A 32 dp visual rail on the right shows user and assistant nodes, highlights the current node, opens a tooltip on tap, copies the selected node content into the editor, and supports long-press scrubbing with feedback. | The tooltip must stay inside the viewport. Provide a list or sheet fallback for TalkBack and large-font layouts. |
| Footer actions | Two equally weighted actions: Continue and Confirm. Both stop voice capture first. Confirm sends the composed response; Continue sends the continue action with current text/options. | Disable or show progress while the exact invocation is awaiting authoritative ACK. Never relabel Continue as an infinity glyph. |
| Project picker | List active projects with name, task title, path, current indicator, and sent/waiting indicator. Selecting one sends a scoped switch/sync request and closes the sheet. | Use a modal bottom sheet or full-height dialog with loading, empty, error, and retry states. |
| Settings and pairing | Connection endpoint/status, connect/disconnect, secure pairing link import/validation, and debug-only notification/clear-message actions. Credentials remain in Android secure storage. | Manual endpoint entry belongs under advanced/diagnostics once secure pairing works. Pairing errors must distinguish malformed, expired/used, rejected, unreachable, and credential-revoked states. |
| Usage quota | A project-header long press opens a sheet of provider status, account label, summary, remaining percentages, and reset labels. Empty/stale/error data is explicit. | Use a discoverable overflow or labeled action in addition to long press so TalkBack and keyboard users can reach it. Never infer account state from color alone. |
| Codex Live goal | Show the current goal title, phase/status, progress, plan completion, elapsed time, token budget/usage, and deep-link affordance when supplied. Updates are associated with their goal/request identity. | Adapt to a compact card or sheet; keep stale/completed states distinct and validate deep links before leaving the app. |
| Ghost completion and speech assistance | Offer synchronized command completion, explicit acceptance, editable/enabled suggestion management, and visible speech listening/error/retry states. Speech learning and corrections may sync through the paired Bridge but never auto-send the response. | Use Android IME/accessibility semantics; keep completion acceptance separate from submit, and expose management/recovery without relying on a gesture alone. |
| Home/overview | Loads the authenticated Bridge `/mobile` route, exposes only the documented prompt/speech/training/ghost/Home request allowlist to page content, and returns to the conversation when requested or when a new MCP request arrives. | WebView navigation is limited to the paired origin; external links leave the app; back navigates WebView history before closing Home. Validate method/path/body limits before forwarding any native request. |

## Visual system

Use the following iOS colors as cross-platform semantic tokens. Compose may map them to a Material color scheme, but components must read tokens rather than hard-coded colors.

| Token | Light | Dark |
| --- | --- | --- |
| Background | `#FFFFFF` | `#000000` |
| Secondary background | `#F9FAFB` | `#111111` |
| Card | `#F3F4F6` | `#1A1A1A` |
| Primary text | `#1F2937` | `#FFFFFF` |
| Secondary text | `#6B7280` | `#9CA3AF` |
| Border | `#E5E7EB` | `#333333` |
| Light border | `#D1D5DB` | `#444444` |
| Active background | `#000000` | `#FFFFFF` |
| Active text | `#FFFFFF` | `#000000` |
| Accent | `#3B82F6` | `#3B82F6` |
| Connected/success | `#10B981` | `#10B981` |
| Connecting/warning | `#F59E0B` | `#F59E0B` |
| Disconnected/error | `#EF4444` | `#EF4444` |

Initial geometry targets:

- Screen horizontal padding: 16 dp; header horizontal padding: 12 dp.
- Header visual icon circle: 32 dp inside a minimum 48 dp hit target.
- Card and main action radius: 8 dp; compact action radius: 6 dp.
- Message card padding: 16 dp.
- Editor visible height: roughly 120–180 dp before internal scrolling.
- Voice visual circle: 56 dp with a minimum 56 dp target.
- Footer padding: 16 dp; Continue and Confirm have equal width.
- Timeline visual width: 32 dp with extra semantic/touch space as needed.

Typography follows the platform font. Preserve hierarchy and relative emphasis rather than copying point sizes blindly. At 1.3× font scale, no primary action, status, or project identity may be clipped or overlap.

## State model and action contract

The UI must distinguish at least these states:

| State | Visible result | Allowed actions |
| --- | --- | --- |
| Unpaired | Pairing-required status and an entry to secure pairing | Import/scan pairing, open diagnostics |
| Pairing | Progress and cancellable validation | Cancel; do not open a second claim |
| Pairing failed | Specific error and recovery action | Retry with a new grant when expired/used |
| Connecting | Amber status, retained local draft | Settings, cancel navigation; no duplicate connect |
| Connected and idle | Green status, empty-state resync | Resync, switch project, settings |
| Active request | Full workbench | Edit, attach, select, Continue, Confirm |
| Awaiting ACK | Blue sent status; request and draft remain associated with the invocation | No duplicate primary action; allow recovery/navigation |
| Accepted ACK | Remove exactly the accepted invocation and reset only its draft | Show concise success feedback |
| Rejected or stale | Keep request/draft, show reason, request authoritative sync | Retry only after refreshed state/revision |
| Reconnecting/offline | Orange/red status, preserve content and selected project | Manual retry, settings; automatic bounded recovery |
| Credential revoked | Explicit re-pair requirement | Clear invalid credential and pair again |

Every outgoing action for the current protocol includes the exact `invocation_id` and `state_revision` when supplied. Do not clear a new-protocol request optimistically. Remove it only after the desktop Bridge returns the authoritative action result. Legacy `request_id` compatibility may remain isolated and tested, but it cannot weaken new invocation behavior.

## Data requirements from the Bridge

Extend the Android model/parser only as Issue #1 makes these fields available:

- Request identity: `id`/`request_id`, `invocation_id`, `state_revision`.
- Context: `project_path`, `project_id`, `project_display_name`, MCP host ID/label, host session ID, task ID/display name, created time, and deadline.
- Workbench: message, input placeholder, predefined options, custom prompts, and timeline snapshot/delta.
- Assistance and status: ghost-suggestion store, quota snapshot/providers/status label, and Codex Live goal snapshot.
- Results: action accepted/rejected/idempotent, pending-invocation snapshot, connection lifecycle, and credential revocation.
- Project list: request identity, project name/path, task title, current state, and sent/waiting state.

Unknown fields remain forward-compatible. An empty or unrelated message must not erase the currently active request.

## Implementation sequence

### Phase 0 — Lock fixtures and navigation

1. Add deterministic preview/test fixtures for idle, active request, long Markdown, options, templates, timeline, offline, dark mode, and large font.
2. Replace boolean route/theme flags with explicit navigation and appearance state.
3. Define a reducer or equivalent pure state transition layer before adding more callbacks.
4. Decide one Android back order: image preview → sheet/dialog → keyboard → Home WebView history → Home route → app background.

Acceptance: previews are deterministic; no fixture content can appear in a production Bridge request.

### Phase 1 — Theme and responsive shell

1. Replace static `IosParityColors` reads with light/dark semantic tokens.
2. Rebuild the header with current actions and responsive overflow.
3. Add accurate empty, unpaired, connecting, connected, reconnecting, sent, and disconnected presentation.
4. Add IME and system inset handling.

Acceptance: light/dark and 1.0×/1.3× font screenshots pass at 360×800 and 412×915 without overlap.

### Phase 2 — Request card and composer

1. Render sanitized Markdown, selectable text, code, links, and authenticated images.
2. Implement image preview, Upload image, @File, Copy source, and Quote source.
3. Implement the multiline composer, picked/pasted images, removal, voice insertion, and server placeholder.
4. Implement ordered option rows, quick templates with reorder, and two-dimensional conditional prompt state.
5. Implement ghost completion acceptance and speech states without coupling either to submission.
6. Replace the old footer with Continue/Confirm and authoritative ACK behavior.

Acceptance: no hard-coded request text; all content comes from fixtures or Bridge state; duplicate taps cannot complete an invocation twice.

### Phase 3 — Secondary native surfaces

1. Implement the active-project picker with scoped switching and sync.
2. Implement timeline snapshot/delta rendering, tap, tooltip, scrub, and accessible fallback.
3. Implement Settings with connection, secure pairing, and debug-only controls.
4. Add usage-quota and Codex Live goal surfaces, including stale/error/completed states.
5. Restrict Home WebView to the authenticated selected Bridge endpoint and its explicit native-request allowlist.

Acceptance: switching project never shows another project's request or timeline as authoritative; temporary placeholders are visually identified as loading.

### Phase 4 — Pairing and lifecycle integration

1. Consume the pairing payload forwarded by `PairingActivity` in both cold and warm starts.
2. Store scoped credentials using Android Keystore-backed storage.
3. Bind HTTP, WebSocket, Home WebView, project list, files, prompts, images, and actions to the selected authenticated endpoint.
4. Recover through background, lock, network change, process recreation, and credential revocation without duplicate actions.

Acceptance: complete the physical-device checklist in Issue #1. UI parity is not complete while the app still depends on loopback or unauthenticated endpoints.

### Phase 5 — Evidence and cleanup

1. Remove obsolete mock callbacks, hard-coded examples, and unreachable Web-first/Compose-first branches.
2. Capture an Android reference set for every state in the screenshot matrix below.
3. Perform TalkBack, keyboard, font-scale, rotation, and real-device checks.
4. Update README status only after build and physical-device evidence exists.

## Expected file map

Existing files likely to change:

- `app/src/main/java/com/kexin94yyds/iterate/MainActivity.kt` — pairing intent consumption, warm-start intents, system back.
- `app/src/main/java/com/kexin94yyds/iterate/PairingActivity.kt` — validated handoff only.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/AndroidMobileWorkbenchApp.kt` — top-level navigation and lifecycle effects.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/WorkbenchModels.kt` — explicit immutable UI/request/action states.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/BridgeViewModel.kt` — reducer orchestration, draft ownership, exact-once actions.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/BridgeJsonParser.kt` — current request metadata, prompts, timeline, snapshots, and ACK results.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/BridgeClient.kt` — one authenticated endpoint/session and lifecycle recovery.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/AndroidMobileTheme.kt` — semantic light/dark tokens.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/WorkbenchScreen.kt` — responsive workbench layout.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/WorkbenchComponents.kt` — split as components become independently testable.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/MobileWebViewScreen.kt` — paired origin, auth, navigation policy.
- `app/src/main/java/com/kexin94yyds/iterate/mobile/VoiceInputController.kt` — permission/error/retry lifecycle.

Prefer small focused files such as `ui/RequestCard.kt`, `ui/Composer.kt`, `ui/TimelineRail.kt`, `ui/ProjectPickerSheet.kt`, `ui/SettingsSheet.kt`, and `ui/ImagePreview.kt` once `WorkbenchComponents.kt` becomes difficult to review. The names are suggestions, not a required package reorganization.

## Test and evidence plan

### Unit tests

- Parse all current request identity/context fields and ignore unrelated messages without clearing state.
- Preserve server order for options and user order for selected output.
- Build Continue and Confirm payloads with `invocation_id` and `state_revision`.
- Reduce accepted, idempotent, rejected, stale, pending-snapshot, reconnect, and revoked-credential events.
- Keep per-invocation drafts and per-project timelines isolated.
- Verify prompt reorder and conditional active/value semantics.
- Verify ghost completion matching/acceptance and suggestion management without implicit submission.
- Reduce fresh/stale/error quota snapshots and running/completed live-goal snapshots without cross-request leakage.
- Verify voice transcript insertion never auto-sends.

### Compose UI and screenshot tests

- Idle, unpaired, connecting, active, awaiting ACK, rejected/stale, reconnecting, and revoked states.
- Short and very long project/task labels; empty and many option rows.
- Long Markdown, code block, link, authenticated image placeholder/success/failure, and image overlay.
- Light/dark at 360×800 and 412×915; portrait/landscape; 1.0× and 1.3× font scale.
- Project picker, Settings/pairing errors, timeline tooltip/scrub, quota sheet, live-goal states, ghost completion, and Home WebView back/allowlist behavior.
- Semantics assert names, roles, selected/disabled states, reading order, and minimum target size.

Use the repository's chosen screenshot framework; this plan does not require a specific new dependency. Golden images require human review and do not replace behavior assertions.

### Required physical-device evidence

- Fresh install and pairing on a phone with no development loopback assumptions.
- Text, one/many options, Continue, Confirm, cancellation/recovery, attachments, file mention, and voice confirmation.
- Background, lock, Wi-Fi/cellular transition, process recreation, and revoked credential.
- Duplicate-tap and stale-revision attempts complete the original request no more than once.
- TalkBack traversal and 1.3× font scale on the smallest supported width.

Recommended local commands remain:

```bash
./gradlew :app:testDebugUnitTest
./gradlew :app:assembleDebug
```

Add focused connected/UI test commands to each implementation PR as those tests appear.

## PR slicing and ownership

1. **PR A — state fixtures, semantic theme, and responsive shell.** No networking claims.
2. **PR B — request rendering, composer, attachments, prompts, voice, and Continue/Confirm.** Uses fixtures plus parser/reducer tests.
3. **PR C — project picker, timeline, Settings, and authenticated Home navigation.** Requires matching Bridge payload fixtures.
4. **PR D — pairing/lifecycle integration and physical-device evidence.** Coordinates with Issue #1 and is the first PR allowed to claim end-to-end parity.

Each PR must stay on a feature branch, include before/after evidence, and avoid force-pushing `main`. A partial PR must state which parity rows remain incomplete.

## Definition of done

- Every Surface Contract row has implementation evidence and a named test or physical-device check.
- Android has no hard-coded demo task, loopback production endpoint, or unauthenticated fallback.
- Compose workbench and WebView Home follow the agreed boundary; there is no unresolved Web-first/Compose-first split.
- Light/dark, insets, IME, rotation, font scaling, TalkBack, and system back are verified.
- Continue/Confirm actions are identity-bound and clear only after authoritative ACK.
- Project, request, draft, and timeline state never leak across projects or invocations.
- Quota, live-goal, and synchronized assistance state is identity-scoped, accessible, and never presented as fresher than its source timestamp permits.
- Secure pairing and credential revocation satisfy Issue #1.
- No private source, credentials, tokens, signing data, local paths, APKs, or build outputs are committed.
- README status is updated from “seed” only after automated checks and the physical Android checklist pass.

## Explicit non-goals

- Rebuilding the full desktop iterate UI on Android.
- Copying `NativeMainPageView` or historical onboarding prototypes.
- Publishing the app, adding production credentials, or changing repository visibility.
- Declaring iOS/Android parity from emulator screenshots alone.
- Replacing the authenticated pairing work in Issue #1 with a UI-only shortcut.

# iOS UI Reference Snapshot

This directory contains verbatim source snapshots from the user-verified iterate iOS personal-development UI. The product owner explicitly approved publishing this minimum UI reference set to help Android contributors implement the [iOS-to-Android UI parity plan](../../ios-ui-parity-plan.md).

This snapshot corrects the source-selection error in pull request #3. That pull request copied an older 1,804-line workbench from an unrelated dirty working tree. The files below come from the Build 19 product line that was subsequently installed and accepted on a physical iPhone.

## How to use these files

- Treat them as visual, interaction, and state-reference material.
- Recreate the documented behavior with Jetpack Compose and Android platform conventions.
- Do not add these Swift files to the Android build or translate them line by line.
- When this snapshot and the parity plan appear to differ, follow the parity plan. The plan defines the approved Android product boundary and acceptance criteria.
- Issue #1 remains authoritative for secure pairing, endpoint selection, credentials, invocation identity, acknowledgement, and lifecycle recovery.

## Snapshot provenance

- Source repository: `kexin94yyds/iterate`
- Product UI source commit: `17efc534a4a62dd779a4af8f92051e3b48d26a09`
- Installed verification commit: `873ce7fce840c278ba7d2829b4c4bfaadc8a874e`
- Snapshot date: 2026-09-04
- Snapshot type: committed personal-development Build 19 source, not an App Store release
- Integrity: each copied file is byte-for-byte identical to its source at snapshot time; SHA-256 values are listed below

The installed verification commit adds only APNs identity recovery code outside this five-file UI set. A path-scoped comparison confirmed that every included file is identical at both commits. The hashes below identify the exact reference content supplied to Android contributors.

## Included files

| File | What it demonstrates |
| --- | --- |
| [`ContentView.swift`](ContentView.swift) | Current workbench hierarchy; route focus; request card; composer; attachments; voice and speech learning; options; prompts; ghost completion; project/file selection; settings; quota sheet; Codex Live state; phone-action feedback; watch relay; footer actions; theme tokens; image preview. |
| [`MarkdownView.swift`](MarkdownView.swift) | Markdown blocks, selectable text, code, links, cached inline images, authenticated remote-image presentation, and selection-aware source actions. |
| [`MCPMessage.swift`](MCPMessage.swift) | UI-facing request/response fields plus timeline route identity, custom prompts, ghost suggestions, provider quotas, and Codex Live goal snapshots. |
| [`Views/TimelineDotBar.swift`](Views/TimelineDotBar.swift) | Timeline node rail, active state, tooltip, tap-to-compose, long-press scrubbing, and haptic feedback. |
| [`MainPageView.swift`](MainPageView.swift) | Authenticated Home WebView boundary; navigation policy; allowlisted prompt, speech-memory, speech-training, ghost-settings, and Home request bridges; return-to-conversation behavior. |
| [`LICENSE`](LICENSE) | MIT license notice covering this source snapshot. |

## Deliberately excluded

The snapshot does not include:

- `WebSocketManager.swift` or the full Bridge transport implementation;
- Keychain, device credential, private-key, pairing-proof, APNs, or push implementation;
- app entitlements, signing, release, hosted control-plane, or production environment configuration;
- app assets, screenshots, private diagnostics, or the historical iOS onboarding prototypes;
- `NativeMainPageView.swift`, which is outside the approved Android parity scope.

The included source may reference omitted types such as `WebSocketManager`, `DeviceAuthStore`, `ServerConfig`, `SpeechRecognitionManager`, `CodexLiveManager`, `NotificationManager`, or Bridge authorization helpers. That is intentional: this is not a standalone iOS project. Some UI files also contain local state helpers and allowlisted request adapters needed to understand visible behavior; they do not include usable credentials. Do not recreate missing security or networking behavior from guesses; follow Issue #1 and the parity plan.

## Integrity manifest

| File | SHA-256 |
| --- | --- |
| `ContentView.swift` | `d83e0c3c495ecb8c3e891da30cd67e4ee604ebb0791573fb98094fd657376be5` |
| `MarkdownView.swift` | `d113cec1b3d47db52377662c4b66ebf7b99cdde5980ff990756170204920a5b2` |
| `MCPMessage.swift` | `e813c6a9c11533500439c2fb4fa565013855edf98e8e2da381e00ab55acd40bc` |
| `Views/TimelineDotBar.swift` | `50a5aa4d7db87d84bba52be82d56d14b698efc5591eff93f69f50d52818cc6f6` |
| `MainPageView.swift` | `98aaec918ab96ed0861a01360157728b8e96c832b7b71f1d46149e8ba8f74a3a` |
| `LICENSE` | `ac18099706256975b7f8de0e88506072618f2a05ef422f1974956040e31508ab` |

To verify the copied files after checkout:

```bash
shasum -a 256 docs/reference/ios-ui/ContentView.swift \
  docs/reference/ios-ui/MarkdownView.swift \
  docs/reference/ios-ui/MCPMessage.swift \
  docs/reference/ios-ui/Views/TimelineDotBar.swift \
  docs/reference/ios-ui/MainPageView.swift \
  docs/reference/ios-ui/LICENSE
```

## Update rule

Do not silently edit these snapshot files. If the iOS source of truth changes materially, create a new reviewed snapshot commit, update every affected hash, summarize the behavior changes, and re-check the Android parity plan before replacing the reference.

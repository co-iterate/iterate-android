# iOS UI Reference Snapshot

This directory contains verbatim source snapshots from the current iterate iOS companion UI. The product owner explicitly approved publishing this minimum UI reference set to help Android contributors implement the [iOS-to-Android UI parity plan](../../ios-ui-parity-plan.md).

## How to use these files

- Treat them as visual, interaction, and state-reference material.
- Recreate the documented behavior with Jetpack Compose and Android platform conventions.
- Do not add these Swift files to the Android build or translate them line by line.
- When this snapshot and the parity plan appear to differ, follow the parity plan. The plan defines the approved Android product boundary and acceptance criteria.
- Issue #1 remains authoritative for secure pairing, endpoint selection, credentials, invocation identity, acknowledgement, and lifecycle recovery.

## Snapshot provenance

- Source repository: `kexin94yyds/iterate`
- Source working-tree HEAD: `ec9fc1d9a8a25c6c13a451fa9d0bd9e7ab0fee89`
- Snapshot date: 2026-09-04
- Snapshot type: current working-tree files, not a claim about a released App Store build
- Integrity: each copied file is byte-for-byte identical to its source at snapshot time; SHA-256 values are listed below

Several source files had local, uncommitted iOS changes at snapshot time. The hashes below, not the repository HEAD alone, identify the exact reference content supplied to Android contributors.

## Included files

| File | What it demonstrates |
| --- | --- |
| [`ContentView.swift`](ContentView.swift) | Current workbench hierarchy; header; request card; composer; images; voice; options; prompt templates; conditional context; project picker; settings; footer actions; theme tokens; full-screen image preview. |
| [`MarkdownView.swift`](MarkdownView.swift) | Markdown blocks, selectable text, code, links, images, and authenticated remote-image presentation. |
| [`MCPMessage.swift`](MCPMessage.swift) | UI-facing request, host/task identity, invocation, revision, deadline, option, and prompt fields. |
| [`Views/TimelineDotBar.swift`](Views/TimelineDotBar.swift) | Timeline node rail, active state, tooltip, tap-to-compose, long-press scrubbing, and haptic feedback. |
| [`MainPageView.swift`](MainPageView.swift) | The narrow Home WebView boundary and return-to-conversation behavior. |
| [`LICENSE`](LICENSE) | MIT license notice covering this source snapshot. |

## Deliberately excluded

The snapshot does not include:

- `WebSocketManager.swift` or the full Bridge transport implementation;
- Keychain, device credential, private-key, pairing-proof, APNs, or push implementation;
- app entitlements, signing, release, hosted control-plane, or production environment configuration;
- app assets, screenshots, private diagnostics, or the historical iOS onboarding prototypes;
- `NativeMainPageView.swift`, which is outside the approved Android parity scope.

The included source may reference omitted types such as `WebSocketManager`, `SpeechRecognitionManager`, `NotificationManager`, or Bridge authorization helpers. That is intentional: this is not a standalone iOS project. Do not recreate missing security or networking behavior from guesses; follow Issue #1 and the parity plan.

## Integrity manifest

| File | SHA-256 |
| --- | --- |
| `ContentView.swift` | `2413d0aefff23a075ef5991258c259f2dc36ff335a9847f89419f5f2bcfb1f39` |
| `MarkdownView.swift` | `3f5c7a19bd5f7488668034cc17d50d3c4fe3a5386ed65a38ca88577511df9369` |
| `MCPMessage.swift` | `da680dd11755ca37dbb5d8ff1f9cc64fd273d5eb1db59ee039c6918a707dcc75` |
| `Views/TimelineDotBar.swift` | `802a3274c50982c2edf9ad2421a5c424998a99a1ca24e670475a3ba73bff5d0c` |
| `MainPageView.swift` | `4727cae75438249c91e75c126b792c9e14183f19501020be762f84151729849a` |
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

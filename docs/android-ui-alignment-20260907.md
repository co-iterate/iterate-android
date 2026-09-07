# Android workbench UI alignment — 2026-09-07

## Scope

Align the native Android workbench with the owner’s current iOS 1.0.1 (19)
interface. This delivery covers Android UI; desktop installation and real
pairing integration are outside this change.

## Changes

- Compact header actions with 48 dp touch targets, project expansion indicator,
  and wrapping at narrow widths or large font sizes.
- Light/dark semantic colors and matching system bars.
- Native Markdown rendering with tables, selectable content, copy and quote.
- Image selection, preview and removal; path picker; per-project draft state.
- Active projects open near full height with a fixed title/close row and no search.
- Four request actions use 32 dp visual height inside 48 dp touch targets.
- Full-width option rows, reply editor scrolling above the keyboard, and footer
  controls clear of system navigation.
- Integrated semicircular voice dock and a shared infinity outline with lighter
  optical weight; header/footer use 20/22 size proportions.

## Validation

- Debug app and instrumentation APK builds pass.
- 10 JVM tests and 8 Android 14 emulator UI tests passed during this iteration.
- Focused keyboard visibility recheck passed after the editor-scroll adjustment.
- Focused option-selection test passed after the final infinity adjustment;
  light and dark screenshots were inspected.
- Original navigation regression reproduced before the fix: Confirm extended
  88 pixels below the safe boundary. The updated layout passes.
- Large-font (1.3×), idle, project panel and path picker previews were inspected.
- Final debug APK and installed emulator APK SHA-256 match:
  `c0947f82e758808d794d122522fddb1ad0eabf6902ce05a593bdcd937da68cf3`.
- Debug signature verified; release merged manifest excludes the preview activity.

`WorkbenchPreviewActivity` is a debug-only host with explicit local preview
fixtures. It does not contact a desktop. Normal launch uses real connection state.

## Integration limits

Secure pairing, desktop attachment reception, project synchronization and server
ACK recovery have not been verified end to end. Existing client wiring supports
these UI controls, but enqueue success is not a server acknowledgement. Failed
sends preserve drafts. No desktop app was installed or restarted for this delivery.

The Markdown renderer uses CommonMark Java with the tables extension. Remote
Markdown images open as links. Physical-device validation and release signing
remain outside this UI delivery.

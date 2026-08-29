# iterate Android

Private development repository for the iterate Android companion.

## Status

This repository is a guarded, standalone Android handoff seed. The historical Compose source and JVM tests have been imported without the private monorepo's Tauri/Rust build shell.

The historical implementation currently lives in the private iterate monorepo and has an unresolved product split:

- the last emulator-verified runtime used a Web-first mobile workbench;
- the later checked-in baseline uses a Compose-first workbench;
- neither baseline has completed current physical-device parity with the iOS companion.

Imported source provenance:

- private source repository: `kexin94yyds/iterate`
- authoritative source branch at extraction: `codex/final`
- historical Android source commit: `18fba149e5891241c0f458e9c58265e6a425a538`
- extraction date: 2026-08-29

Do not publish or mirror the historical monorepo while resolving this split. This seed is intentionally missing the private desktop, iOS, hosted control-plane, release, and credential-handling implementation.

## Product contract

The Android app is a mobile companion, not a scaled desktop client. It should:

- pair securely with a desktop iterate Bridge;
- store scoped device credentials securely;
- render waiting MCP requests and predefined options;
- submit, continue, or cancel the exact request once;
- support voice input with explicit user confirmation;
- recover from foreground, background, lock, and network transitions;
- reject revoked or stale credentials;
- avoid the desktop activation gate.

## Import boundary

Only import the minimum buildable Android client and shared protocol contracts. Do not copy the entire private monorepo.

The current seed is structurally standalone, but a clean Kotlin/Gradle build has not been rerun after extraction because the source machine had less than 1 GiB free disk space. Do not treat this import commit as a build receipt.

Never commit:

- production credentials, device tokens, signing keys, or environment files;
- local SDK paths, IDE state, Gradle caches, build outputs, APKs, AABs, or JNI binaries;
- private control-plane or release infrastructure that the Android client does not need to compile and test.

## Collaboration

- Repository visibility: Private
- Product owner / administrator: `kexin94yyds`
- Android developer: `YunQI-1` with Write access after accepting the repository invitation
- Changes should use small branches and pull requests; no force-push to `main`.

The first implementation pull request should contain a behavior matrix, source provenance, automated checks, and a physical Android device acceptance checklist.

## Local setup

Prerequisites:

- Android Studio or Android SDK 36
- JDK 17
- the repository Gradle wrapper

Create `local.properties` with your local SDK path or set `ANDROID_HOME`, then run:

```bash
./gradlew :app:testDebugUnitTest
./gradlew :app:assembleDebug
```

The imported app currently points its Bridge client and Home WebView at `127.0.0.1:8080`. That is historical behavior, not the target mobile architecture. The first product PR must replace it with authenticated pairing to the selected desktop endpoint before claiming an end-to-end connection.

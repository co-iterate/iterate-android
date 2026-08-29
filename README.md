# iterate Android

Private development repository for the iterate Android companion.

## Status

This repository is a guarded handoff container. The Android source has not been imported yet.

The historical implementation currently lives in the private iterate monorepo and has an unresolved product split:

- the last emulator-verified runtime used a Web-first mobile workbench;
- the later checked-in baseline uses a Compose-first workbench;
- neither baseline has completed current physical-device parity with the iOS companion.

Do not publish or mirror the historical monorepo while resolving this split.

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

# Implement — OpenVibeBoard release readiness

Implementation starts only after the user reviews these artifacts and `task.py start release-readiness` changes the task to `in_progress`.

## Success checkpoints

### 1. Configurable serial device

- Add the serial-path preference and pure selection policy.
- Update `SerialMonitor` to publish available/configured paths, observe ORSSerialPort manager changes, and switch ports without restart.
- Add the Device settings destination and inject the shared monitor into the Settings scene.
- Keep the key-mapping schema and fixed baud rate unchanged.
- Add selection-policy and reconnect/switch-state tests at the pure boundary.
- Update the serial/directory/error-handling specs for the new source of truth.

Validation:

```bash
xcodegen generate
xcodebuild test -project OpenVibeBoard.xcodeproj -scheme OpenVibeBoard -derivedDataPath .build/DerivedData
```

Manual gates:

- Saved port survives app restart.
- Switching between an unavailable path and the attached ESP32 updates status without app restart.
- Disconnect/reconnect restores the configured device.
- Physical button events still dispatch after switching.

Checkpoint commit: `feat: add configurable serial device`

### 2. Build, install, and visual QA

- Build Release from the checkpoint commit and reinstall `/Users/ethereal/Applications/OpenVibeBoard.app`.
- Verify version `0.2.0 (1)`, entitlements, launch, Settings navigation, device selection, key mapping editor, and Accessibility link.
- Capture `docs/images/settings-device.png` and `docs/images/settings-key-mappings.png` from this installed build at a consistent window size.
- Inspect both images before documentation use.

No commit until the screenshots are confirmed current and free of private/transient content.

### 3. Documentation and release notes

- Add both screenshots to English and Chinese README files.
- Replace hardcoded serial-path instructions with UI selection behavior.
- Document manual GitHub Releases updates and the current ad-hoc/notarization boundary.
- Update both changelogs and the roadmap so completed work is not left as pending.

Validation:

```bash
rg -n '/dev/cu\.usbmodem3101|Sparkle|GitHub Releases|settings-device|settings-key-mappings' README.md README.zh-CN.md CHANGELOG.md CHANGELOG.zh-CN.md
```

Checkpoint commit: `docs: add release screenshots and distribution guidance`

### 4. Continuous integration

- Add `.github/workflows/ci.yml` for project generation and tests.
- Add the exact workflow badge to both README files.
- Validate YAML and run the same commands locally.
- Push the commit, then require the GitHub Actions run on `master` to finish successfully; local success alone is insufficient.

Checkpoint commit: `ci: add macOS build and test workflow`

### 5. Packaging and credential-gated distribution

- Add `scripts/package-release.sh` with fail-loud `adhoc` and `developer-id` modes.
- Add `.github/workflows/release-artifact.yml` with ephemeral keychain cleanup and explicit secret contract.
- Add generated build/dist paths to `.gitignore`.
- Run the ad-hoc path from a clean checkout state and verify app metadata, entitlement output, `codesign`, archive contents, and checksum.
- Exercise the Developer ID path without credentials and require an early non-zero failure with a clear missing-prerequisite message.
- Do not dispatch the release workflow and do not claim notarization success.

Validation evidence:

```bash
SIGNING_MODE=adhoc scripts/package-release.sh
codesign --verify --deep --strict <staged-app>
codesign -d --entitlements :- <staged-app>
shasum -a 256 -c <checksum-file>
SIGNING_MODE=developer-id scripts/package-release.sh  # expected fail: credentials absent
```

Checkpoint commit: `build: add release packaging and notarization workflow`

### 6. Integration validation and Draft Release

- Run `trellis-check`, full tests, Release build, packaging validation, and documentation link checks.
- Confirm `git status` is clean, `project.yml` is `0.2.0 (1)`, and all commits are pushed to `origin/master`.
- Wait for the pushed CI workflow to pass.
- Generate the final ad-hoc/unnotarized test artifact from that exact commit.
- Create bilingual draft notes with the trust warning at the top.
- Create the Draft Release for intended version `v0.2.0`; attach only the test zip and checksum.
- Verify through `gh release view --json` / GitHub API that it remains draft and targets the expected commit.
- Verify no local or remote `v0.2.0` Git tag was created.

External-state rollback:

```bash
gh release delete v0.2.0 --repo Ethereal49/openvibeboard --yes
```

Use only if draft creation/upload verification fails; no tag deletion should be needed.

### 7. Finish Trellis work

- Update specs with durable serial/release conventions discovered during implementation.
- Record notarization as blocked by missing Developer ID/App Store Connect credentials, not as a skipped success.
- Archive the task, record the journal, commit task metadata separately, and push.

Checkpoint commit: `chore(task): archive release readiness`

Journal commit, if Trellis creates a separate workspace change: `chore: record journal`

## Files with elevated risk

- `OpenVibeBoard/Serial/SerialMonitor.swift`: stale delegate callbacks and reconnect races can overwrite live status.
- `OpenVibeBoard/OpenVibeBoardApp.swift`: the menu and Settings scenes must share the same monitor instance.
- `project.yml`: signing overrides must preserve the serial entitlement and keep normal CI independent of local identities.
- `.github/workflows/release-artifact.yml`: temporary keychain/private key files must always be deleted.
- `scripts/package-release.sh`: Developer ID mode must never downgrade silently to ad-hoc.

## Hard completion boundary

This task can complete the code, CI, ad-hoc test package, and Draft Release. It cannot complete Developer ID signing, notarization, staple, or Gatekeeper approval without credentials. Those four checks remain explicitly blocked and the Draft Release must not be published as a production release.

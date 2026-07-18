# Design — OpenVibeBoard release readiness

## Architecture boundaries

This task adds one runtime preference and one release pipeline without changing the key-mapping protocol:

```text
UserDefaults.serialPortPath
        ↓
SerialMonitor (@MainActor, source of truth)
  ├─ ORSSerialPortManager.availablePorts → availablePaths
  ├─ configuredPath → open / close / reconnect
  └─ published status → MenuBarView + SettingsView

config.json → ConfigStore → key mappings (unchanged)
```

Release delivery remains outside the app:

```text
clean pushed commit
  → macOS CI build/test
  → package-release.sh
       ├─ ad-hoc test path (available now)
       └─ Developer ID + notarization path (credential-gated)
  → checksums
  → Draft GitHub Release v0.2.0
```

Sparkle and update keys are deliberately absent. v0.2.0 updates are downloaded manually from GitHub Releases.

## Serial preference and state ownership

### Persistence

- Store only the selected serial path in `UserDefaults` under a namespaced key such as `serialPortPath`.
- Do not add device settings to `config.json`: that file is the stable, v0.1-compatible physical-key mapping schema.
- Keep baud rate fixed at `115200`; the firmware protocol does not expose a user need for changing it.

### Path selection policy

Extract a deterministic pure function and cover it with tests:

1. A non-empty saved path wins, even if currently unavailable. This preserves explicit user intent and lets the UI show that the chosen device is disconnected.
2. With no saved path, choose the lexicographically first available `/dev/cu.usbmodem*` path.
3. With no matching available path, fall back to the historical `/dev/cu.usbmodem3101` path so existing behavior remains recognizable.

Paths shown in the picker are sorted. If the configured path is unavailable, keep it as a disabled-state/current-selection row instead of silently switching devices.

### Port discovery

- Use the pinned ORSSerialPort 2.1.0 API: `ORSSerialPortManager.shared().availablePorts`.
- Initialize the singleton once in `SerialMonitor`; this also enables the library's close-on-sleep/reopen-on-wake behavior.
- Observe `ORSSerialPortsWereConnectedNotification` and `ORSSerialPortsWereDisconnectedNotification`, then rebuild `availablePaths` from the manager.
- A newly connected device matching `configuredPath` triggers an immediate connection attempt instead of waiting for the five-second retry.

### Switching and reconnect flow

`SerialMonitor` remains the single owner of the active `ORSSerialPort` and exposes read-only published state plus `selectPort(path:)`:

1. Ignore selection of the existing path.
2. Cancel pending reconnect work.
3. Detach/close the old port and clear the active reference.
4. Persist and publish the new path; clear stale event/error presentation.
5. Open the new path immediately when available, otherwise stay disconnected and retain it as the configured target.
6. Existing runtime errors continue to schedule five-second reconnects.

Delegate callbacks must ignore stale port instances by identity. This prevents a delayed close/error callback from the old port overwriting the status of the newly selected port.

### Settings UI

- `SettingsView` becomes a native macOS settings `TabView` with two destinations: Device and Key Mappings.
- Device presents connection status and a serial-port `Picker`; it does not duplicate key-mapping controls.
- Key Mappings embeds the existing sidebar-detail workflow unchanged.
- Inject the app-owned `SerialMonitor` into the `Settings` scene so the menu and Settings always show the same live state.
- Keep the configured unavailable path visible with an unavailable label. Port changes apply immediately; there is no extra Save button for this single preference.

## Documentation assets

Use `docs/images/` as the stable repository-owned asset directory:

- `settings-device.png` — serial selection and connection state.
- `settings-key-mappings.png` — current key mapping editor and keycaps.

Capture both from the freshly rebuilt and installed v0.2.0 app after UI/hardware validation. Use a consistent window size and redact no content by post-processing; recapture if private or transient content is present. Both README variants reference these files through relative paths.

## GitHub Actions

### Continuous integration

Add `.github/workflows/ci.yml`:

- Trigger on pushes to `master` and pull requests.
- Run on a pinned supported macOS runner.
- Install `xcodegen`, generate the project, then run `xcodebuild test` for the shared scheme with a deterministic DerivedData path.
- Require no serial hardware, Accessibility permission, signing identity, or notarization secret.
- Add matching CI badges to both README variants.

### Credential-gated release artifact workflow

Add a manual `.github/workflows/release-artifact.yml` that imports a Developer ID certificate into an ephemeral keychain and creates a `notarytool` profile from App Store Connect API credentials. Its inputs/secrets are explicit and non-interactive:

- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `NOTARYTOOL_KEY_ID`
- `NOTARYTOOL_ISSUER_ID`
- `NOTARYTOOL_PRIVATE_KEY_BASE64`

The workflow calls the same local packaging script and uploads only validated outputs. It is added but not dispatched in this task because the required credentials do not exist.

## Packaging and trust modes

Add `scripts/package-release.sh` with explicit modes:

### `SIGNING_MODE=adhoc`

- Build Release configuration from `project.yml`/generated Xcode project.
- Apply ad-hoc signing with the existing serial entitlement.
- Validate bundle version, bundle identifier, bundle structure, entitlements, and `codesign --verify --deep --strict`.
- Create `OpenVibeBoard-0.2.0-macos-adhoc-unnotarized.zip` and a SHA-256 checksum file.
- Do not run or claim `notarytool`, staple, or Gatekeeper acceptance.

This is the only locally executable release path in the current environment and its output is a test artifact, not a production installer.

### `SIGNING_MODE=developer-id`

- Fail before building if `DEVELOPER_ID_APPLICATION` or notarization credentials are absent.
- Build with Developer ID Application signing, hardened runtime, secure timestamp, and the existing entitlements.
- Verify the designated requirement and authority chain for the app and nested code.
- Package with `ditto`, submit via `xcrun notarytool --wait`, staple the app, run `xcrun stapler validate`, and require `spctl --assess --type execute` success.
- Repackage the stapled app and generate the final checksum only after every trust check succeeds.

No branch silently falls back from Developer ID to ad-hoc signing.

Generated build/dist directories stay gitignored. Scripts print the exact artifact paths and trust status, and exit non-zero on skipped required checks.

## Draft Release contract

- Create a Draft GitHub Release whose target commit is the clean, pushed `master` commit and whose intended tag name is `v0.2.0`.
- Do not create or push a Git tag while the release remains a draft and lacks a notarized production artifact.
- Attach the ad-hoc/unnotarized test zip and checksum with bilingual release notes that state the trust boundary before installation instructions.
- Record build-from-source instructions and Accessibility/serial requirements.
- Verify the draft through the GitHub API after upload: `isDraft`, target commit, asset names, sizes, and checksums.

## Compatibility and migration

- Existing `config.json` files are untouched and remain decodable.
- Existing users without a serial preference get the historical device-selection behavior plus automatic `/dev/cu.usbmodem*` discovery.
- Existing ad-hoc local installs remain usable. Moving later to Developer ID changes the code-signing identity and may require Accessibility permission to be granted again; release notes must warn when that transition happens.

## Rollback

- Serial preference: reverting code restores the historical hardcoded path; the unused `UserDefaults` key is harmless.
- CI/workflows/scripts/docs are independent commits and can be reverted separately.
- Draft Release can be deleted without deleting a Git tag because no tag is created during this task.
- A failed Developer ID/notarization run uploads nothing and leaves no public Release.

## Trade-offs

| Decision | Choice | Consequence |
|---|---|---|
| Device persistence | `UserDefaults` | Keeps mapping schema stable; preference is machine-local |
| Missing saved device | Preserve selection | No surprise device switch; user must choose another port |
| Settings structure | Device + Key Mappings tabs | Native and simple; adds one top-level navigation layer |
| Update strategy | GitHub Releases manually | No in-app prompt; avoids Sparkle/key lifecycle before distribution trust exists |
| Current artifact | Ad-hoc, unnotarized test zip | Useful for validation, unsuitable as a normal public installer |
| Release state | Draft, no Git tag | Preserves v0.2.0 for a later credential-backed production release |

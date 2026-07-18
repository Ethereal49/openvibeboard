**English** | [简体中文](./CHANGELOG.zh-CN.md)

# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Native combination-key recording with macOS-style keycaps and multi-modifier support.
- A direct Accessibility settings action that launches System Settings and opens the correct privacy pane.
- Configurable serial-device selection with persistence, discovery, and live reconnect.
- macOS CI plus explicit ad-hoc and credential-gated Developer ID packaging workflows.

### Changed

- Replaced the vertically stacked mapping form with a sidebar-detail Settings layout and a fixed save bar.
- Removed the duplicate About tab in favor of the standard macOS About panel.
- Simplified menu bar status and permission text.
- Documented GitHub Releases as the manual update channel; an in-app updater remains deferred.

## [0.2.0] - 2026-07-07

The project was rewritten as a native SwiftUI macOS menu bar app.

### Rewritten

- Added a SwiftUI `MenuBarExtra` utility with launch-at-login support through `SMAppService`.
- Replaced the Python serial loop with `ORSSerialPort` and Swift reconnect handling.
- Unified `tap` and `hold` keyboard injection through `CGEvent`, with modifier flags attached to the character keydown.
- Replaced the Web UI with a native SwiftUI Settings scene and a persistent `config.json` schema compatible with v0.1.
- Added `cmd`, `key`, and `text` actions plus `tap` and `hold` key modes.
- Renamed VibeBoard to OpenVibeBoard to avoid Accessibility TCC confusion with an existing `/Applications/VibeBoard.app`.

### Tests

- Added Swift Testing coverage for `parseKey`, Codable round trips, serial line parsing, action decisions, and injected config storage.
- Extracted pure functions and injected storage URLs to make behavior testable while keeping CGEvent, Process, pasteboard, login-item, and hardware checks as manual gates.

### Changed

- Archived the v0.1 Python implementation under `archive/python-v0.1/`.

## [0.1.0] - 2026-07-03

Initial open-source release.

### Added

- Single-process `vibe_control.py` daemon with an HTTP configuration service at `127.0.0.1:8765` and a serial listener.
- `cmd`, `key`, and `text` actions with `tap` and `hold` modes.
- Web configuration UI with hot reload, physical key recording, and text actions.
- Clipboard-based text injection through `pbcopy` and `Cmd+V` to bypass Chinese input method conversion.
- ESP-IDF serial parsing for `button down kN` and `button up kN` events.
- `event.code` based combination-key recording to avoid macOS Option key layout issues.
- Reproducible Python environments managed with `uv` and `uv.lock`.

[0.2.0]: https://github.com/Ethereal49/openvibeboard/releases/tag/v0.2.0
[0.1.0]: https://github.com/Ethereal49/openvibeboard/releases/tag/v0.1.0

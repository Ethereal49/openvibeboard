**English** | [简体中文](./CONTRIBUTING.zh-CN.md)

# Contributing

Thanks for helping improve OpenVibeBoard. Keep changes focused and explain the user-facing reason for each change.

## Development Setup

```bash
git clone https://github.com/Ethereal49/openvibeboard.git
cd openvibeboard
brew install xcodegen
xcodegen generate
open OpenVibeBoard.xcodeproj
```

Development requires macOS 15+, Xcode 16+, and Accessibility permission for runtime keyboard injection. `ORSSerialPort` is resolved automatically through Swift Package Manager.

## Project Conventions

Trellis specs under `.trellis/spec/` are the source of truth for implementation conventions:

- [`backend/`](.trellis/spec/backend/) covers Swift app structure, the `CGEvent` modifier flag contract, serial handling, config persistence, actor isolation, and logging.
- [`guides/`](.trellis/spec/guides/) contains cross-layer and code-reuse checklists.

Read the relevant spec before editing code. Keep SwiftUI scene structure explicit, keep AppKit bridges narrow, and preserve the existing config schema unless a migration is planned.

## Testing

Run the full test target before submitting a change:

```bash
xcodegen generate
xcodebuild test -project OpenVibeBoard.xcodeproj -scheme OpenVibeBoard
```

Pure logic is covered by Swift Testing. Changes to `KeyInjector`, `ActionDispatcher`, `CmdRunner`, serial handling, or permissions also need the relevant manual check described in `.trellis/spec/backend/quality-guidelines.md`.

For input injection changes, manually verify `cmd`, `key` tap, `key` hold, and `text`. The `key` hold path is especially important: press and hold the physical button, confirm the modifier remains active, then release it and confirm no modifier state leaks into the next event.

## Commit Guidelines

- Keep commits small and scoped to one concern.
- Explain what changed and why in the commit message.
- Do not edit the generated `OpenVibeBoard.xcodeproj` by hand; update `project.yml` and regenerate it.
- Do not add a new dependency without explaining the need and updating `project.yml`.
- If a serial parser branch changes, add or update the corresponding test in `OpenVibeBoardTests/`.

## Reporting Issues

Include the macOS version, Xcode version, keyboard model, serial path, the exact mapping, and relevant log output. Do not include private configuration values or credentials.

## Pull Requests

Describe the behavior change, list the validation commands, and call out any manual hardware or permission checks that were not available. Keep unrelated formatting or generated-file changes out of the pull request.

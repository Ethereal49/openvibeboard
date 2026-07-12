**English** | [简体中文](./README.zh-CN.md)

# OpenVibeBoard

> Take over an ESP32-S3 keyboard on macOS without changing its firmware. Map physical buttons to shell commands, keyboard events, or text input.

OpenVibeBoard is a native Swift menu bar app. It listens to the keyboard's USB CDC log, dispatches configured actions, and provides a native Settings window. The Swift implementation replaced the archived Python v0.1 client.

## Features

- Persistent menu bar utility with optional launch at login via `SMAppService`.
- USB CDC serial monitoring through `ORSSerialPort`.
- Native SwiftUI Settings for key mappings with explicit save and live reload.
- Three action types: `cmd` (shell command), `key` (keyboard event), and `text` (clipboard paste).
- Two key modes: `tap` and `hold`.
- Chinese-friendly text input through `NSPasteboard` + `Cmd+V`, avoiding input method conversion.

## Requirements

- macOS 15 or later.
- Xcode 16 or later.
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- The keyboard must expose its ESP-IDF log through `/dev/cu.usbmodem3101` (or the path configured in the source).
- The serial device must not be held by another program.

## Build and Run

```bash
git clone https://github.com/Ethereal49/openvibeboard.git
cd openvibeboard
xcodegen generate
open OpenVibeBoard.xcodeproj
```

Run the `OpenVibeBoard` scheme with `Cmd+R`. The menu bar icon appears after launch. On the first run, grant Accessibility permission in System Settings -> Privacy & Security -> Accessibility. The menu bar item includes a direct link to that pane when permission is missing.

You can also build from the command line:

```bash
xcodebuild -project OpenVibeBoard.xcodeproj -scheme OpenVibeBoard build
```

## How It Works

The keyboard emits lines such as:

```text
button down k1
button up k1
```

The app parses those events, looks up the matching `KeyConfig`, and dispatches the action through `ActionDispatcher`:

```text
MenuBarExtra
  -> SerialMonitor
  -> ActionDispatcher
       -> CmdRunner       (cmd)
       -> KeyInjector     (key)
       -> TextInjector    (text)
ConfigStore actor         ~/Library/Application Support/OpenVibeBoard/config.json
```

## Actions and Modes

| Type | Behavior | Example |
| --- | --- | --- |
| `cmd` | Run a shell command without blocking the UI | `open -a Codex` |
| `key` | Send a keyboard event through `CGEvent` | `ctrl+c`, `option+d`, `esc` |
| `text` | Paste text through the clipboard | `继续` |

`key` actions support `tap` (keydown followed by keyup) and `hold` (keydown until the physical button is released). Modifier flags are attached to the character key event so they do not leak into later events.

The Settings recorder accepts combinations such as `cmd+shift+d`; users do not need to type the configuration syntax manually.

For `text` actions, `enter` controls whether the app sends Return after pasting. The `mode` field is only meaningful for `key` actions.

## Default Mappings

| Button | Default action |
| --- | --- |
| `k1` | `cmd`: `open -a Codex` |
| `k2` | `text`: paste `继续` and press Return |
| `k3` | `key` tap: `ctrl+c` |
| `k4` | `key` hold: `option+d` |

Mappings are stored in `~/Library/Application Support/OpenVibeBoard/config.json`. The schema remains compatible with the Python v0.1 configuration.

## Permissions and Troubleshooting

- **Accessibility**: required for `key` actions and the `Cmd+V` part of `text` actions. Use the menu bar item's `打开授权设置…` action or open System Settings -> Privacy & Security -> Accessibility manually.
- **Apple Events**: shell commands that invoke `osascript` or AppleScript may request Automation permission.
- **Serial connection fails**: release `/dev/cu.usbmodem3101` from `screen`, Arduino IDE, the Python client, or another serial tool, then reconnect the keyboard.
- **A key stops working**: check the serial connection first, then inspect the mapping in Settings.
- **A hold combination emits only one character or leaves a modifier stuck**: verify that the event went through `KeyInjector`; modifier flags must be attached to the character keydown.

## Development

Trellis stores project conventions in `.trellis/spec/`. Read the relevant spec before changing the app.

```bash
xcodegen generate
xcodebuild test -project OpenVibeBoard.xcodeproj -scheme OpenVibeBoard
```

The archived Python implementation is under [`archive/python-v0.1/`](archive/python-v0.1/).

## Roadmap

- Package, sign, notarize, and publish GitHub releases.

## License

[MIT](LICENSE)

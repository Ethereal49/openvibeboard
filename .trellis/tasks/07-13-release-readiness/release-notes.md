# OpenVibeBoard v0.2.0 (Draft)

> Test build only / 仅供测试
>
> The attached app is ad-hoc signed and unnotarized. macOS Gatekeeper is expected to reject it. It is not a production installer.
>
> 附件仅使用 ad-hoc 签名且未经 Apple 公证，macOS Gatekeeper 拒绝是预期结果。它不是生产安装包。

## English

OpenVibeBoard v0.2.0 replaces the Python daemon with a native SwiftUI menu bar app for macOS 15 and later.

### Highlights

- Native menu bar utility with launch-at-login support.
- Configurable USB serial-device selection with persistence and live reconnect.
- Native Settings for key mappings, including macOS-style combination-key recording.
- `cmd`, `key`, and `text` actions with `tap` and `hold` modes.
- Direct navigation to the Accessibility privacy pane.
- macOS CI plus reproducible ad-hoc and credential-gated Developer ID packaging workflows.

### Test artifact

1. Verify the downloaded zip against its `.sha256` file.
2. Extract `OpenVibeBoard.app` and move it to Applications.
3. Grant Accessibility permission under System Settings -> Privacy & Security -> Accessibility.
4. Select the ESP32-S3 serial device under Settings -> Device.

For a trusted build, clone the repository and build from source. A Developer ID signed and notarized artifact remains blocked until distribution credentials are available.

## 简体中文

OpenVibeBoard v0.2.0 将 Python 守护进程重写为 macOS 15+ 原生 SwiftUI 状态栏 App。

### 主要变化

- 原生状态栏常驻，并支持应用内开机自启。
- Settings 可选择 USB 串口，选择结果持久化，并支持拔插热重连。
- 原生按键映射界面，可直接录制并显示 macOS 组合键 keycap。
- 支持 `cmd`、`key`、`text` 三类动作，以及 `tap`、`hold` 两种按键模式。
- 可直接进入系统的辅助功能授权页面。
- 新增 macOS CI，以及可重复的 ad-hoc / Developer ID 凭据门控打包流程。

### 测试附件

1. 使用 `.sha256` 文件验证下载的 zip。
2. 解压 `OpenVibeBoard.app` 并移入 Applications。
3. 在系统设置 -> 隐私与安全性 -> 辅助功能中授权 OpenVibeBoard。
4. 在 Settings -> 设备中选择 ESP32-S3 串口。

需要可信构建时请从源码编译。Developer ID 签名与 Apple 公证产物仍受分发凭据缺失阻塞。

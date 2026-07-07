# 技术设计（Swift 原生）

## 架构

SwiftUI app：`@main` App + `MenuBarExtra` 场景 + `Settings` 场景。后台 `Task` 监听串口，按 config 分发动作（CGEvent / Process / NSPasteboard）。`SMAppService` 管登录项。

## 文件结构

```
VibeBoard.xcodeproj
VibeBoard/
  VibeBoardApp.swift         @main：MenuBarExtra + Settings 场景
  MenuBarView.swift          状态栏菜单（状态/开关/退出）
  SettingsView.swift         配置面板（按键映射 Form）
  Models/
    Config.swift             Codable KeyConfig + Application Support 持久化
    KeyCodes.swift           virtual key codes + modifier 映射（复刻 KEY_CODES/CHAR_CODES）
  Serial/
    SerialMonitor.swift      ORSSerialPort 封装，解析 button down/up
  Actions/
    ActionDispatcher.swift   按 config 分发：cmd→Process, key→CGEvent, text→NSPasteboard+Cmd+V
    KeyEvent.swift           CGEvent tap/hold（复刻 hold_down 的 flags 挂载）
  LaunchAtLogin.swift        SMAppService.mainApp register/unregister
VibeBoardTests/
  ConfigTests / KeyCodesTests / ProtocolTests / ActionDispatcherTests
```

## 关键设计

### 串口监听
- ORSSerialPort（SPM）打开 `/dev/cu.usbmodem3101`，按行回调。
- 正则 `button (down|up) (k\d)` → ActionDispatcher（移植 Python `DOWN_RE/UP_RE`）。

### CGEvent 按键（核心坑复刻）
- hold 组合键：`CGEventCreateKeyboardEvent` + `CGEventSetFlags` 在 char event 上挂 modifier flag，**不**单独发 modifier keydown —— 复刻 Python `hold_down` 的核心约定（这是 Python 版最深坑，Swift 必须逐行对照）。
- tap：单次 key event。
- modifier 映射：cmd/ctrl/option/shift → 对应 CGEventFlags。

### text 动作
- `NSPasteboard.general.clearContents()` + `setString(text)` + CGEvent 发 Cmd+V + 可选 Enter。
- 复刻剪贴板绕输入法方案。

### 配置
- `Codable struct KeyConfig { type, value, mode?, enter?, desc }`，`[String: KeyConfig]`。
- `FileManager.url(for:.applicationSupportDirectory)` → `VibeBoard/config.json`。
- 首次运行写默认配置（移植现有 config.json）。

### 应用内自启
- `SMAppService.mainApp().register()/unregister()`。
- 菜单 Toggle 绑定；状态查询 `SMAppService.mainApp().status`。

### 构建
- Xcode build → `VibeBoard.app`，拖 `/Applications` 即用。

## 实现时需 context7 查证的 API

- SwiftUI `MenuBarExtra` / `Settings` 当前用法。
- `SMAppService`（ServiceManagement）注册/状态。
- `ORSSerialPort` SPM 集成 + API。
- `CGEvent` Swift bridging（CoreGraphics）。

## 兼容性 / 迁移

- 主分支变 Swift；Python 代码移 `archive/python-v0.1/`（或 `python-legacy` 分支），git 历史完整。
- config.json schema 兼容（键名/字段一致）；首次运行可检测旧位置（项目根）并迁移。
- 最低 macOS 13（Ventura）。

## 选型理由

- SwiftUI MenuBarExtra vs AppKit NSStatusItem：SwiftUI 现代简洁，macOS 13+ 足够。
- ORSSerialPort vs IOKit：省几百行 IOKit 样板，成熟开源。
- SMAppService vs LaunchAgent：Apple 推荐的当代登录项 API，应用内管理，体验远优于手写 plist。

## 回滚

- Swift 重写前，Python 版在 git 历史（commit ead213c/2ad740c）+ `python-legacy` 分支保留。
- 失败可回 Python 分支继续用 v0.1.0。

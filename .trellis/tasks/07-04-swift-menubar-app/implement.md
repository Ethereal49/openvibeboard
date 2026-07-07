# 执行计划（Swift 重写）

跨多次会话。按阶段提交，每阶段独立验证。

## 阶段

### A. Xcode 项目骨架 + 配置模型
- 建 `VibeBoard.xcodeproj`（SwiftUI app，deployment macOS 13，`MenuBarExtra`）。
- `Config.swift`（Codable）+ Application Support 持久化。
- context7 查 `MenuBarExtra`。
- **验证**：构建 .app，状态栏图标出现。

### B. 串口监听（ORSSerialPort）
- SPM 加 ORSSerialPort。
- `SerialMonitor`：开 `/dev/cu.usbmodem3101`，按行解析 `button down/up`。
- context7 查 ORSSerialPort。
- **验证**：跑 .app，按物理键，菜单/日志显示按键事件。

### C0. 改名 OpenVibeBoard（阶段 C 实测前置，✅ 已完成）
- 撞车发现：`/Applications/VibeBoard.app` 是别人家的 app（`app.vibeboard.mac`，TeamID 3W2AKHD5H2，v0.5.4），Accessibility TCC 授权混淆。
- 改名范围：目录 `VibeBoard/`→`OpenVibeBoard/`、`struct VibeBoardApp`→`OpenVibeBoardApp`、bundle id `com.ethereal49.OpenVibeBoard`、PRODUCT_NAME / display name / entitlements / Application Support 目录。
- 白名单不动：`vibe_control.py` / README / CHANGELOG / CONTRIBUTING。
- 主会话裁决（规则 7）：tap 也走 CGEvent（合并注入路径，spec 意图"按 mode 二选一"仍满足，字面"tap 走 osascript"是 Python 历史包袱，留阶段 G 修订 spec）。
- 验证：构建 + 阶段 A/B 串口回归通过。

### C. CGEvent 按键注入（核心硬门，✅ 已完成，实测门通过）
- `KeyEvent.swift`：tap + hold（`CGEventSetFlags` 挂 modifier，复刻 Python `hold_down`）。
- `ActionDispatcher`：cmd→Process, key→tap/hold, text→NSPasteboard+Cmd+V。
- **对照 Python `vibe_control.py` 逐行复刻 flags 坑**。
- **验证**：四种动作（k1 cmd / k2 text / k3 tap / k4 hold）实测通过。

### D. SwiftUI Settings 配置面板
- `SettingsView`：Form 编辑按键映射，热生效。
- 替代 index.html + HTTP server。
- **实测发现（2026-07-06）**：`NSApp.sendAction(Selector(("showSettingsWindow:")))` 在 macOS 26 返回 `true` 但**不打开** Settings 窗口（NSApp.windows 只剩 36×30 状态栏图标窗口）。Apple 已弃用该 selector 路径。改用 SwiftUI 官方 `@Environment(\.openSettings)`（macOS 14+）→ 实测打开 900×450 Settings 窗口（CGWindowList onscreen 确认）。**deployment target 因此从 13 提到 14**。
- **验证**：✅ Settings 窗口打开（自动触发 + CGWindowList onscreen 双确认）；✅ 物理键改配置热生效实测通过（2026-07-06）。

### E. SMAppService 应用内自启（✅ 已完成，实测门通过）
- `LaunchAtLogin.swift`：`SMAppService.mainApp` register/unregister + 状态查询（enum + 静态方法，对齐 `Permissions/Accessibility.swift` 风格）。
- 菜单 Toggle（computed `Binding`，getter 每次重读 `status` 不缓存，用户在系统设置改过也同步）。
- context7 查 `SMAppService`（API + Status 枚举 + 6 个坑见 `research/smappservice-launch-at-login.md`）。
- **验证**：✅ 勾选 → 系统设置「登录项」出现 OpenVibeBoard；✅ 注销重登 → 自启（2026-07-07）。
- **构建坑（重要，F 阶段也会踩）**：Xcode 16 **Debug Dylib Support**（`ENABLE_DEBUG_DYLIB`）—— Debug 构建把项目代码全编进 `OpenVibeBoard.debug.dylib`，主 `Contents/MacOS/OpenVibeBoard` 只是 ~57KB launcher stub。**验证符号要 `nm .debug.dylib`，nm 主二进制会误判「代码没编进去」**（实测踩过）。Release 构建无此机制，产出单体二进制。

### F. Swift Testing 测试（✅ 已完成 2026-07-07；框架改 Swift Testing；用户拍板范围）
- 范围（详见 `research/swift-testing.md`，含 API + 重构方案 + 全分支测试表）：
  - **纯逻辑直测**：`KeyInjector.parseKey`（核心 flags 坑的纯侧，参数化）、`KeyConfig`/`Config` Codable（Python schema 兼容）、`defaultConfig`（守护 k1-k4 迁移意图）
  - **小重构后测**：`ConfigStore`（注入 URL，默认值保持现状）、`SerialMonitor.parseLine`（从 delegate 抽纯函数）
  - **重构 `ActionDispatcher`**：抽 `decideAction` 纯函数 + `Action` 枚举，`fireDown/fireUp` 改 decide→execute（**行为不变**，C 实测门仍是权威），参数化测全分支（type/mode/未知 type/parseKey nil/up 只对 hold）
- **不测**（实测门已覆盖）：`KeyInjector.tap/press/release`、`CmdRunner`、`TextInjector`、`LaunchAtLogin`、`SerialMonitor` 端口/重连/delegate
- xcodegen `project.yml` 加 `OpenVibeBoardTests` target（`bundle.unit-test`，Xcode 16+ 内置 Swift Testing）
- **验证**：✅ `xcodebuild test` **30 tests / 5 suites 全绿**（2026-07-07，主会话独立复核，非 sub-agent 自报）。重构行为不变：`decideAction` 分支语义 1:1 对照原 `fireDown/fireUp`，`KeyInjector`/`CmdRunner`/`TextInjector` 调用未变，`parseKey` 由 `DispatchQueue.global` 移到 main actor（纯函数无影响），C 实测门仍是权威。F 无硬件实测门（纯测试），全绿即闭环。

### G. 文档 + Python 归档 + 提交
- README/CHANGELOG 改 Swift（Xcode 构建/安装/权限主体变化）。
- Python 代码移 `archive/python-v0.1/` 或 `python-legacy` 分支。
- `.trellis/spec/`（Python 约定）标记作废，随 Swift 代码沉淀新 spec。
- 提交（无 Co-Authored-By）。

## Review Gate

- **C 是核心硬门**：四种动作实测通过才算基础完成。
- 每阶段独立提交。

## 风险缓解

- ORSSerialPort（B）：备选 IOKit 原生。
- CGEvent 权限：.app 首次运行弹辅助功能授权，README 说明。
- 重写规模：分阶段，每阶段可验证 + 提交，不追求一次完成。
- Swift 不熟：实现时 context7 查每个 framework 的当前 API。

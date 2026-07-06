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
- **验证**：设置面板改配置，物理键触发新动作。

### E. SMAppService 应用内自启
- `LaunchAtLogin.swift`：register/unregister + 状态查询。
- 菜单 Toggle。
- context7 查 `SMAppService`。
- **验证**：勾选 → 注销重登 → 自启。

### F. XCTest 测试
- Config/KeyCodes/Protocol/ActionDispatcher tests。
- mock CGEvent/Process/Serial。
- **验证**：`xctest` 全绿。

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

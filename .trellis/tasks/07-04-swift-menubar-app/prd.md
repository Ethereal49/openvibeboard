# v0.2.0: Swift 原生 macOS 状态栏 app（应用内自启 + 测试）

## Goal

把 VibeBoard 从 Python 守护进程**重写为 Swift/SwiftUI 原生 macOS menu bar 应用**：`MenuBarExtra` 状态栏、CGEvent 原生按键注入、ORSSerialPort 串口监听、SwiftUI Settings 配置面板、`SMAppService` 应用内管理开机自启、XCTest 测试。现有 Python 实现（`vibe_control.py` / `index.html`）作为逻辑参考，重写后归档。

## Requirements

### R1. 原生 menu bar app
- SwiftUI `MenuBarExtra` 状态栏图标 + 菜单（状态、打开设置、开机启动开关、退出）。
- 后台串口监听（async/Task），解析 `button down kN` / `up kN`。
- CGEvent（CoreGraphics）原生实现 tap/hold 按键注入，**复刻 Python 版的 modifier flags 坑处理**。
- 三种动作：`cmd`（Process）/ `key`（CGEvent tap+hold）/ `text`（NSPasteboard + Cmd+V）。

### R2. 应用内自启
- `SMAppService.mainApp.register()/unregister()`，菜单加「开机启动」开关。
- 用户在「系统设置 → 通用 → 登录项」看到 VibeBoard，系统级管理。
- **不写** launchd plist / 外部脚本。

### R3. SwiftUI Settings 配置面板（替代 Web UI）
- `Settings { ... }` 场景，原生表单编辑按键映射。
- Codable JSON 持久化到 `~/Library/Application Support/VibeBoard/config.json`。
- index.html + HTTP server **废弃**。

### R4. XCTest 测试
- 纯逻辑：config Codable、按键映射表、协议正则、动作分发（mock CGEvent/Process/Serial）。

## 关键决策

- **SwiftUI MenuBarExtra + Settings**（macOS 13+）。
- **SMAppService**（macOS 13+）：应用内登录项，替代 launchd。最低部署 macOS 13。
- **ORSSerialPort**（SPM 第三方库）：替代 pyserial。备选 IOKit。
- **CGEvent 原生**：CoreGraphics 直接调；现有 flags 坑用 Swift 逐行复刻。
- **text 动作**：NSPasteboard + Cmd+V，复刻剪贴板绕输入法方案。
- **config.json**：迁到 `~/Library/Application Support/VibeBoard/`。
- **Web UI 废弃**：SwiftUI Settings 替代，HTTP server/index.html 不再需要。
- **构建**：Xcode 项目（生成 .app 最直接）。
- **Python 资产**：`vibe_control.py` / `index.html` / `pyproject.toml` / uv / Python spec **归档**到 `archive/python-v0.1/` 或 `python-legacy` 分支（git 历史完整保留），作 Swift 重写的逻辑参考。

## 风险

- **重写规模**：约 800-1200 行 Swift，跨多次会话。
- **ORSSerialPort 集成**：SPM 依赖，需验证 ESP32-S3 CDC 兼容。
- **CGEvent 权限**：辅助功能授权对象变 .app bundle，首次运行弹窗。
- **Swift 学习曲线**（若不熟）。
- **text 动作中文**：NSPasteboard + Cmd+V 应同样绕输入法，需复测。

## Acceptance Criteria

- [ ] Xcode 构建出 `VibeBoard.app`，双击运行出状态栏图标。
- [ ] 菜单：状态、设置、开机启动开关、退出。
- [ ] 串口监听 + 四种动作（cmd / key tap / key hold / text）实测通过。
- [ ] Settings 面板编辑配置热生效。
- [ ] 「开机启动」勾选 → SMAppService 注册 → 注销重登自启。
- [ ] `xctest` 跑通（config/映射/协议/分发）。
- [ ] README/CHANGELOG 更新为 Swift 构建/安装说明。
- [ ] Python 代码归档，主分支是 Swift。

## Out of Scope

- 多 modifier 组合键、GitHub Release v0.1.0、串口路径可配置、README 截图（路线图计划中）。
- CI、自动更新（Sparkle）。
- iOS 移植。

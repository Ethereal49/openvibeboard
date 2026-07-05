# 阶段 A 研究：MenuBarExtra + 项目骨架

> 给 trellis-implement sub-agent 的外部 API 参考 + 项目骨架决策。
> Python 业务逻辑 spec（CGEvent flags / config schema / 协议解析）在 implement.jsonl 已指向，不在此重复。

## 项目骨架生成：用 xcodegen（已装 2.45.4）

**不要手写 `.xcodeproj/project.pbxproj`**（易错且难维护）。仓库根建 `project.yml`，跑 `xcodegen generate` 声明式生成 `VibeBoard.xcodeproj`。

`project.yml` 起步模板（sub-agent 按需调整，但保留关键 key）：

```yaml
name: VibeBoard
options:
  bundleIdPrefix: com.ethereal49
  deploymentTarget:
    macOS: "13.0"
  developmentLanguage: zh-Hans
settings:
  base:
    MARKETING_VERSION: "0.2.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "5.0"   # 先用 Swift 5 mode，避免 Swift 6 并发严格性踩坑
targets:
  VibeBoard:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: VibeBoard
    info:
      path: VibeBoard/Info.plist
      properties:
        CFBundleDisplayName: VibeBoard
        LSUIElement: true            # ★ menu bar app 必需：accessory 模式，不在 Dock 显示、无主窗口
        LSMinimumSystemVersion: "13.0"
        NSAppleEventsUsageDescription: "VibeBoard 需要发送 Apple 事件以执行 cmd 动作与按键模拟。"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ethereal49.VibeBoard
```

### ★ 关键 plist key（容易漏）
- `LSUIElement: true`：menu bar app 作为 accessory 运行——不在 Dock 显示图标、没有主应用菜单栏。**没这个 key，app 启动会闪一个空窗口 + Dock 图标，不像状态栏 app**。

## MenuBarExtra API（SwiftUI，macOS 13+）

来源：context7 → developer.apple.com/documentation/swiftui/menubarextra

utility app 模式（无 WindowGroup，MenuBarExtra 作唯一主场景）：

```swift
import SwiftUI

@main
struct VibeBoardApp: App {
    var body: some Scene {
        MenuBarExtra("VibeBoard", systemImage: "keyboard") {
            MenuBarView()   // 阶段 A 先放占位菜单
        }
        .menuBarExtraStyle(.menu)   // .menu（下拉菜单）或 .window（popover 窗口）
    }
}
```

- `MenuBarExtra(_ titleKey: LocalizedStringKey, systemImage:) { content }` 是最常用 init。
- macOS 13.0+ 可用（符合 PRD 最低部署要求）。

### ⚠ 待实测：MenuBarExtra + Settings 共存
Apple 文档原文："MenuBarExtra ... should not be used in conjunction with other scene types in your App."

- 这条主要针对 **WindowGroup**（避免既有窗口又有菜单栏）。
- 社区实践：menu bar app 普遍 `MenuBarExtra + Settings` 共存（⌘, 打开设置），实测可用。
- **阶段 A 先只做 MenuBarExtra（单 scene）**；阶段 D 加 Settings 时实测，若冲突 → 改用独立 `NSWindow`/`NSPanel` 或 `.menuBarExtraStyle(.window)` 内嵌设置。

## Config 模型（阶段 A 要写）

字段 schema **必须兼容 Python v0.1 的 `config.json`**（键名/字段一致，便于首启迁移）。具体 schema 见 `.trellis/spec/backend/directory-structure.md`（implement.jsonl 已指向）。

design.md 草案：
```swift
struct KeyConfig: Codable {
    let type: String        // "cmd" | "key" | "text"
    let value: String       // cmd 串 | key 描述（含 modifier）| 文本
    let mode: String?       // key 动作：tap | hold
    let enter: Bool?        // text 动作：粘贴后是否回车
    let desc: String?       // 用户描述
}
// 顶层：[String: KeyConfig]，key 为按钮名（如 "k1"）
```

持久化：
- `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("VibeBoard/config.json")`
- 首次运行：目录/文件不存在 → 写默认配置（移植 Python 版默认值）。
- 读写加锁（Swift 用 `actor` 或 `NSLock`，对齐 spec 的 CONFIG_LOCK 语义）。

## 构建与验收命令

```bash
xcodegen generate                                    # 生成 .xcodeproj
xcodebuild -project VibeBoard.xcodeproj \
  -scheme VibeBoard -configuration Debug build       # 构建
open "$(xcodebuild -project VibeBoard.xcodeproj -scheme VibeBoard -showBuildSettings -configuration Debug 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3}' | head -1)/VibeBoard.app"
```

**阶段 A 验收**（implement.md）：
1. `xcodegen generate` 成功生成 `.xcodeproj`。
2. `xcodebuild ... build` 成功，无 error。
3. `open .../VibeBoard.app` 运行，状态栏出现 VibeBoard 图标（键盘图标）。
4. 点图标弹出占位菜单（状态/退出）。
5. `~/Library/Application Support/VibeBoard/config.json` 首启被创建，含默认配置。

## 阶段 A 不做（避免范围蔓延）
- 串口监听（B）、CGEvent 注入（C）、Settings 配置面板（D）、SMAppService 自启（E）、XCTest（F）。
- MenuBarExtra 菜单内容：先占位（"状态：开发中"、"关于 VibeBoard"、"退出 VibeBoard"），后续阶段填充真实状态/开关。
- Python 代码归档（G）：本阶段不动。

## 待 sub-agent 实现时验证/反馈的点
- Xcode 26.5 下 deployment target macOS 13 是否有 deprecation 警告（记录，不阻塞）。
- Swift 5 mode 是否需要额外 `@MainActor` 标注（`App` 协议默认 main actor）。
- `LSUIElement` 是否需要配合 `Application is agent (UIElement)` 旧名（Xcode 26 用 LSUIElement 即可）。

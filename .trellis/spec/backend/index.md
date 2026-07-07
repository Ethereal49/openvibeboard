# Backend 开发约定（Swift 原生 macOS 状态栏 app）

> OpenVibeBoard macOS app 的编码约定。v0.2.0 用 Swift/SwiftUI 重写，取代 v0.1 的 Python 守护进程（已归档至 `archive/python-v0.1/`）。

本项目 **不是** 传统后端服务，没有数据库、ORM、迁移、HTTP 路由框架。它是一个原生 macOS menu bar app：`MenuBarExtra` 状态栏 + `Settings` 配置面板 + 后台串口监听 + CGEvent 按键注入。读这里的 spec 之前，先接受这个前提，不要臆造 HTTP 层或服务化抽象。

---

## 技术栈

- **SwiftUI** —— `MenuBarExtra`（状态栏场景）+ `Settings`（配置面板场景），deployment macOS 15
- **ORSSerialPort**（SPM 远程依赖，`armadsen/ORSSerialPort` 2.1.0）—— 串口监听，替代 v0.1 的 pyserial
- **CoreGraphics / CGEvent** —— 原生按键注入（tap + hold），替代 v0.1 的 pyobjc Quartz 包装
- **Carbon.HIToolbox** —— `kVK_ANSI_*` 符号常量（virtual key code），不硬编码 magic number
- **ServiceManagement / SMAppService** —— 应用内登录项（开机自启），替代 launchd plist
- **Swift actor**（`ConfigStore`）—— 配置读写串行化，替代 v0.1 的 `CONFIG_LOCK` + `threading.Lock`

---

## 约定索引

| 文件 | 内容 |
|------|------|
| [Directory Structure](./directory-structure.md) | 模块架构、目录树、分发链、config.json schema |
| [Error Handling](./error-handling.md) | 守护不崩、串口错误码、权限缺失降级、CGEvent nil 守门 |
| [Logging Guidelines](./logging-guidelines.md) | `log()` stderr 包装、何时记、不记什么 |
| [Quality Guidelines](./quality-guidelines.md) | CGEvent modifier flags 坑（最重要）、actor 串行化、权限前置、四动作实测门、禁止模式 |

> 数据库约定：本项目无数据库，`config.json` 是唯一的持久化（键映射配置）。无需 ORM/迁移 spec。

---

**语言**：spec 与代码注释统一用中文。

---

## 与 v0.1 Python 版的关系

v0.1 的 `vibe_control.py`（单文件三职责：HTTP server + 串口线程 + 动作分发）已归档至 `archive/python-v0.1/`，git 历史完整保留。**它仍是 Swift 重写的逻辑参考**——领域知识（CGEvent flags 坑、ESP-IDF button down/up 串口协议、config schema、并发模型）从 Python 视角迁移到 Swift 视角，没有丢弃。

有意偏离 Python 的地方（主会话裁决，非 bug）：
- **tap 也走 CGEvent**：Python 的 tap 用 `osascript keystroke`（Apple Events），Swift 合并到 CGEvent 一条注入路径。spec 字面「tap 走 osascript」是 Python 历史包袱，Swift 版不沿用。
- **配置 UI 改 SwiftUI Settings**：Python 的 `index.html` + HTTP server（`127.0.0.1:8765`）已废弃，Swift 用 `Settings { ... }` 场景 + Form 编辑。
- **并发模型**：Python 用 `threading.Lock` + 守护线程；Swift 用 `actor ConfigStore` 串行化 + `@MainActor` ObservableObject。

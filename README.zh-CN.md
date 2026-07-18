[English](./README.md) | **简体中文**

[![CI](https://github.com/Ethereal49/openvibeboard/actions/workflows/ci.yml/badge.svg)](https://github.com/Ethereal49/openvibeboard/actions/workflows/ci.yml)

# ⌨️ OpenVibeBoard

> 不改固件，给 ESP32-S3 键盘（上游代号 voicestick）做 macOS 端接管：把物理按键映射成 shell 命令、击键或文本输入。

原生 Swift menu bar app：状态栏常驻、串口监听，物理按键即触发动作，配置面板改完热生效。v0.2.0 起 Swift 重写（v0.1 Python 单文件版见 [`archive/python-v0.1/`](archive/python-v0.1/)）。

## 特性

- 📌 **状态栏常驻** —— SwiftUI `MenuBarExtra`，开机可自启（`SMAppService`，应用内勾选，无需改系统文件）
- 🔌 **串口接管** —— 直接读 ESP32-S3 的 USB CDC 日志，不碰固件（ORSSerialPort）
- ⚙️ **原生配置面板** —— sidebar-detail 布局编辑映射，固定保存栏，保存即热生效
- 🎛️ **按键直接录制** —— 点击录制区后按组合键，自动显示 macOS keycap 并生成兼容配置
- ⌨️ **三种动作** —— `cmd`（shell 命令）/ `key`（击键）/ `text`（粘贴文本）
- 🎯 **两种模式** —— `tap`（瞬时）/ `hold`（按住，支持语音软件「按住录音」）
- 🀄 **中文友好** —— `text` 动作走剪贴板粘贴（`NSPasteboard` + `Cmd+V`），绕过中文输入法

## 前提条件

- **macOS 15+**（用 `MenuBarExtra`、SwiftUI Settings、`SMAppService`）
- **Xcode 16+** 与 **[xcodegen](https://github.com/yonaskolb/XcodeGen)**（`brew install xcodegen`）
- 串口 `/dev/cu.usbmodem3101` 未被占用（其他占用该端口的程序需先退出）
- 键盘仍以 ESP-IDF 日志形式输出按键事件（无需改固件）

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/Ethereal49/openvibeboard.git
cd openvibeboard

# 2. 生成 Xcode 工程（读 project.yml）
xcodegen generate

# 3. 用 Xcode 打开，⌘R 运行
open OpenVibeBoard.xcodeproj
```

首次运行：状态栏出现 OpenVibeBoard 图标 → 系统弹「辅助功能」授权（系统设置 → 隐私与安全性 → 辅助功能，勾选 OpenVibeBoard）。授权后物理按键即触发动作。

> 也可命令行构建：`xcodebuild -project OpenVibeBoard.xcodeproj -scheme OpenVibeBoard build`。

## 工作原理

键盘（ESP32-S3）通过 USB CDC 持续输出 ESP-IDF 日志，按键事件行格式：

```
button down kN    # 按下（N = 1-4）
button up kN      # 松开
```

App 架构：

```
MenuBarExtra（状态栏入口）
  └─ SerialMonitor        ORSSerialPort 开 /dev/cu.usbmodem3101，按行解析 button down/up
       └─ ActionDispatcher  查 Config → 分发动作（cmd/key/text）
            ├─ CmdRunner      cmd → Process 执行 shell
            ├─ KeyInjector    key → CGEvent（tap 单发 / hold 按住，CGEventSetFlags 挂 modifier）
            └─ (text)         NSPasteboard 写入 + CGEvent 发 Cmd+V
ConfigStore（actor）        ~/Library/Application Support/OpenVibeBoard/config.json 持久化
```

### 动作类型

| type | 说明 | 触发方式 | value 示例 |
|------|------|----------|-----------|
| `cmd` | Shell 命令 | `Process`（非阻塞） | `open -a Codex` |
| `key` | 击键 | CGEvent（tap / hold 共用注入路径） | `ctrl+c`、`option+d`、`esc` |
| `text` | 输入文本 | 剪贴板 `NSPasteboard` + `Cmd+V`（绕过输入法） | `继续` |

### 模式（仅 `key` 类型有效）

| mode | 行为 | 实现 |
|------|------|------|
| `tap` | 按下即触发一次 | CGEvent 单发 keydown+keyup |
| `hold` | 按下保持 key-down，松开 key-up | CGEvent（modifier 用 `CGEventSetFlags` 挂 flag） |

> `text` 类型用 `enter` 字段（默认 `true`）控制粘贴后是否补一个回车；`mode` 对 `cmd`/`text` 无效。
>
> 注：v0.1 的 `tap` 走 osascript，v0.2 统一走 CGEvent（合并注入路径，flags 处理一致）。

## 配置

状态栏菜单 → **设置…**（或 ⌘,）打开 SwiftUI 配置面板。左侧选择映射，右侧编辑当前动作；保存栏固定在窗口底部，并显示未保存状态。配置持久化在 `~/Library/Application Support/OpenVibeBoard/config.json`（schema 与 v0.1 兼容）。

默认按键映射：

| 键 | 动作 |
|----|------|
| k1 | `cmd`：`open -a Codex` |
| k2 | `text`：粘贴「继续」+ 回车 |
| k3 | `key` tap：`ctrl+c` |
| k4 | `key` hold：`option+d`（语音软件按住录音） |

`key` 类型不需要手动填写 value：点击快捷键录制区，直接按下 `⌘` / `⌃` / `⌥` / `⇧` 与字母或特殊键，界面会显示对应 keycap，并生成 `cmd+shift+d`、`option+d`、`esc` 等规范值。一个或多个 modifier 均支持。

### 应用内开机自启

状态栏菜单 → **登录时启动** 勾选。基于 `SMAppService.mainApp`（注册到系统设置 → 通用 → 登录项），不需 launchd、不改系统文件。再次勾除即取消。

## 权限

首次运行 macOS 会弹授权（系统设置 → 隐私与安全性）：

- **辅助功能** —— 按键注入（`key` tap/hold、`text` 粘贴的 `Cmd+V`）需要；缺失时菜单可直接打开 System Settings 的 Accessibility 页面
- **自动化（Apple 事件）** —— `cmd` 动作里若含 osascript / AppleScript 命令会触发（已声明 `NSAppleEventsUsageDescription`）

> App 为 sandbox（`app-sandbox`）+ 串口 entitlement（`device.serial`），ad-hoc 签名。首次授权辅助功能时若被系统设置忽略，删除该项再勾选一次即可（ad-hoc 签名 TCC 的已知痛点）。

## 故障排查

| 现象 | 原因 / 解决 |
|------|------------|
| 按键无反应 | 多为辅助功能未授权 / 被系统忽略；系统设置 → 辅助功能，删掉 OpenVibeBoard 再勾选 |
| 串口监听不起 | `/dev/cu.usbmodem3101` 被占用，或键盘 USB 断连（拔插键盘重新枚举） |
| 改配置后某键失灵 | 优先排查键盘 USB 重连（按键事件没到），再看配置面板的 value 是否合法 |
| hold 组合键只打出单字符 / 卡住 | 单独发 modifier keydown 的已知坑，本项目用 `CGEventSetFlags` 挂 flag 规避；若复现确认 KeyInjector 路径未被绕过 |
| 「打开授权设置…」无反应 | 确认运行的是最新安装版；该操作会显式启动 System Settings 并打开 Accessibility 页面 |

## 项目结构

```
openvibeboard/
├── project.yml                       # xcodegen 工程描述（target / 依赖 / deployment）
├── OpenVibeBoard.xcodeproj/          # xcodegen 生成（勿手改）
├── OpenVibeBoard/                    # 源码
│   ├── OpenVibeBoardApp.swift        #   App 入口（MenuBarExtra）
│   ├── MenuBarView.swift             #   状态栏菜单
│   ├── Actions/ActionDispatcher.swift#   动作分发（cmd/key/text → 执行）
│   ├── Key/KeyInjector.swift         #   CGEvent 按键注入（parseKey/tap/press/release）
│   ├── Serial/SerialMonitor.swift    #   ORSSerialPort 串口监听 + 行解析
│   ├── Models/Config.swift           #   配置模型 + Application Support 持久化（actor）
│   ├── Settings/                     #   SwiftUI sidebar-detail 配置面板 + AppKit 按键录制桥接
│   ├── LaunchAtLogin/LaunchAtLogin.swift  # SMAppService 自启
│   ├── Permissions/Accessibility.swift#   辅助功能权限检查
│   └── OpenVibeBoard.entitlements    #   sandbox + device.serial
├── OpenVibeBoardTests/               # Swift Testing（parseKey/Codable/parseLine/decideAction 纯逻辑）
├── archive/python-v0.1/              # v0.1 Python 版归档（串口协议 / CGEvent flags 坑作逻辑参考）
└── .trellis/spec/                    # 编码约定（AI sub-agent 自动加载）
```

## 开发

本项目用 Trellis 管理开发流程，编码约定沉淀在 `.trellis/spec/`。改代码前先读对应 spec，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

跑测试：

```bash
xcodegen generate
xcodebuild test -project OpenVibeBoard.xcodeproj -scheme OpenVibeBoard
```

> Xcode 16 Debug 构建启用 **Debug Dylib Support**：项目代码编进 `OpenVibeBoard.debug.dylib`，主 `Contents/MacOS/OpenVibeBoard` 只是 launcher stub。用 `nm` 验证符号要查 `.debug.dylib`，查主二进制会误判「代码没编进去」。Release 构建无此机制。

## 路线图

- [ ] 打包分发（签名 / 公证 / GitHub Release）

## 许可证

[MIT](LICENSE)

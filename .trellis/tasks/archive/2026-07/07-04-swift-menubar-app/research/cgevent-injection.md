# Research: CGEvent 按键注入（阶段 C 核心硬门）

- **Query**: 为 v0.2.0 Swift menu bar app 阶段 C 实现 `KeyEvent.swift`（tap + hold + flags 坑）+ `ActionDispatcher`（cmd→Process / key→tap|hold / text→NSPasteboard+Cmd+V），逐行复刻 Python `vibe_control.py` 的动作分发链。
- **Scope**: mixed（内部 Python 蓝本 + 外部 GitHub 取证 + 本机 SDK header）
- **Date**: 2026-07-05
- **Tool note**: 任务原指定用 context7 查 CoreGraphics/Quartz；本环境 context7 MCP 未返回有效结果（resolve-library-id 对 `CoreGraphics`、`Quartz`、`CGEvent` 均不命中——CoreGraphics 是 Apple 系统框架，不是 SPM 库，context7 索引不到）。所有结论改用 **本机 macOS 26.5 SDK 的 `Events.h` 头文件** + **5 个 GitHub 上真实 Swift CGEvent 项目的取证对比** 得出，比 context7 二手索引更权威。

---

## TL;DR（阶段 C 的 8 条决策）

1. **Sandbox 结论（最关键）**：**保留 sandbox，不动 entitlement**。CGEvent `.post(tap: .cghidEventTap)` 在 `app-sandbox = true` 下完全可用，**不需要** `temporary-exception.mach-lookup-name`、**不需要**关 sandbox、**不需要**额外任何 entitlement。唯一前置是 **Accessibility 权限（TCC，用户授权）**，不是 entitlement。直接证据：`eddmann/ClipVault` 是 sandboxed App Store 风格 menu bar app，entitlements 只有 `app-sandbox + files.user-selected.read-only`，`PasteHelper.swift` 用 `CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true).flags = .maskCommand; .post(tap: .cghidEventTap)` 实测可注入 Cmd+V。详见专节。
2. **flags 坑的 Swift 正确写法**（单 modifier+char，如 `option+d`、`cmd+v`、`ctrl+c`）：在 char 的 keydown 上**直接挂** `.flags`，**不**单独发 modifier keydown/up。这正是 Python `hold_down` 的语义。代码骨架：
   ```swift
   let down = CGEvent(keyboardEventSource: src, virtualKey: charCode, keyDown: true)
   down?.flags = .maskAlternate         // ← flag 直接挂 char keydown
   down?.post(tap: .cghidEventTap)
   // ...
   let up = CGEvent(keyboardEventSource: src, virtualKey: charCode, keyDown: false)
   up?.post(tap: .cghidEventTap)         // ← keyup 不带 flag，对应 Python hold_up
   ```
   注意：CHIMERA 项目（`shivadharmi/CHIMERA`，`KeystrokeInjector.swift:postChord` 注释）实测发现**多 modifier 组合**（Cmd+Shift+P）时纯 `.flags` 方案会让 WindowServer 的 modifier state 残留，导致下一个字符被解释成 chord。本项目 Python 版只支持单 modifier（`hold_down` 的 `key.split("+", 1)` + 单 `_FLAG`），与纯 `.flags` 方案 1:1 对应，**Swift 也只支持单 modifier，沿用纯 `.flags` 即可**。多 modifier 是后续扩展项，不在阶段 C 范围。
3. **tap 动作不要走 CGEvent**。Python 的 `tap` 用 `osascript keystroke`（System Events Apple Event），`hold` 才用 CGEvent。Swift 等价于 `osascript keystroke` 的是 `NSAppleScript`，但它需要 `NSAppleEventsUsageDescription`（已加，见现有 `project.yml`）+ System Events 自动化授权。**更简洁的选择：tap 也用 CGEvent（keydown→立即 keyup）**，跟 hold 走同一条代码路径，只用一份注入实现 + 省掉 AppleScript+Apple Events 的依赖。这是 Python 版因为 `keystroke` 历史才拆成两路的；Swift 重写没这个包袱，可以合并。但这与 Python spec 「tap 与 hold 不可混」冲突——见 spec 冲突处理章节。
4. **virtualKey 用 Carbon `kVK_ANSI_*` 常量**（来自 `HIToolbox/Events.h`，本机 SDK `/Applications/Xcode.app/.../MacOSX26.5.sdk/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/Events.h`）。Swift 直接 `import Carbon.HIToolbox` 后用 `CGKeyCode(kVK_ANSI_A)` 即可，**不要**硬编码 magic number（Python 版 `CHAR_CODES = {"a": 0, ...}` 是硬编码，Swift 直接用 Apple 的符号常量更安全）。
5. **CGEventSource 用 `.hidSystemState`**（对应 Python `kCGEventSourceStateHIDSystemState`），单例化复用（Python `_SRC = CGEventSourceCreate(...)` 顶层模块级，Swift 等价一个 `static let`）。**不要**每次按键都 new source（多余开销且语义不对）。
6. **Accessibility 权限弹窗**：`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true] as CFDictionary)`。一行即可触发系统弹「打开系统设置」对话框。`AXIsProcessTrusted()`（无 Options）只查询不弹窗。两者都用 `ApplicationServices` 框架，Swift `import ApplicationServices` 即可，**不需要** link 整个 Carbon。
7. **cmd 动作用 `Process`**（对应 Python `subprocess.Popen` 非阻塞）。Swift：`let p = Process(); p.launchPath = "/bin/sh"; p.arguments = ["-c", cmd]; try? p.run()`。`run()` 是异步的（对应 Popen），不阻塞串口线程。**不要**用 `Process.run(_:options:)` 的同步重载或 `.waitUntilExit()`——会卡串口线程，违反 spec「cmd 动作必须非阻塞」。
8. **text 动作用 `NSPasteboard` + Cmd+V**（对应 Python `pbcopy + Cmd+V`）。Swift 比 Python 干净：`NSPasteboard.general.clearContents(); .setString(text, forType: .string)` 然后 CGEvent 发 Cmd+V（keyCode 9 = `kVK_ANSI_V`，flag `.maskCommand`）。**不需要** `pbcopy` subprocess。

---

## Python flags 坑机制提炼（蓝本对照）

### 一段话机制

CGEvent 的 modifier 不是独立键的状态，而是 `CGEvent.flags` 属性。当你按物理 `Cmd+V` 时，键盘硬件先发 `Cmd keydown`、再发 `V keydown (flags=Cmd)`、`V keyup (flags=Cmd)`、`Cmd keyup`——WindowServer 跟踪 modifier 状态靠的是 modifier keydown/keyup 配对。但合成事件里如果**单独发 modifier keydown**（不发对应 keyup），WindowServer 会以为 modifier 一直按着，下一个事件全部带 modifier；而如果发 modifier keydown→char keydown→modifier keyup，char keydown 自己没带 flag，目标 app 看 event-level flags 时会丢 modifier。**正确做法是只发一个 char keydown，把 modifier flag 直接挂这个 keydown 上**——系统从 flag 推断 modifier 状态，不发独立 modifier 事件，避免状态残留。`keyup` 不带 flag 即可（让 WindowServer 自动释放）。

### Python 代码引用

`/Users/ethereal/Documents/Code/openvibeboard/vibe_control.py`：

```python
# :48-52  _post —— 关键 helper，CGEventSetFlags 在 keydown 上挂 flag
def _post(code, down, flag=0):
    ev = CGEventCreateKeyboardEvent(_SRC, code, down)   # ← 先 create 键事件
    if flag:
        CGEventSetFlags(ev, flag)                       # ← 再 set flag（挂这个事件上）
    CGEventPost(kCGHIDEventTap, ev)                     # ← 最后 post

# :150-161  hold_down —— 单 modifier 走 _post(cc, True, _FLAG[mod])
def hold_down(key):
    if "+" in key:
        mod = key.split("+", 1)[0].lower()
        cc = _char_code(key)
        if cc is not None:
            _post(cc, True, _FLAG.get(mod, 0))          # ← flag 直接挂 char keydown
    else:
        code = KEY_CODES.get(key.lower()) or CHAR_CODES.get(key.lower())
        if code is not None:
            _post(code, True)

# :164-172  hold_up —— keyup 不带 flag（_post 默认 flag=0）
def hold_up(key):
    if "+" in key:
        cc = _char_code(key)
        if cc is not None:
            _post(cc, False)
    else:
        code = KEY_CODES.get(key.lower()) or CHAR_CODES.get(key.lower())
        if code is not None:
            _post(code, False)
```

要点：
- **`CGEventSetFlags` 调用时机**：必须在 `CGEventCreateKeyboardEvent` 之后、`CGEventPost` 之前（顺序错了 flag 不生效）。
- **`hold_up` 不带 flag**：`_post(cc, False)` 默认 `flag=0`，让系统自动释放 modifier。**不要**在 keyup 上也挂 `.maskAlternate` 等——会让 modifier 状态泄漏到下一次按键（实测验证）。
- **`_FLAG` map 的单 modifier 限制**：`hold_down` 用 `key.split("+", 1)` 切出 mod 和 char，只查 `_FLAG[mod]` 取**一个** flag。多 modifier（`ctrl+shift+d`）的 `_FLAG` 组合是后续扩展，Python 不支持。

`/.trellis/spec/backend/quality-guidelines.md:7-32` 已把这条规则写成 spec（错误写法 vs 正确写法对比），是跨语言约束，Swift 必须遵守。

---

## CGEvent Swift 代码骨架（可直接抄）

### 0. 导入与 source 单例

```swift
import CoreGraphics
import Carbon.HIToolbox          // kVK_ANSI_* 常量
import ApplicationServices       // AXIsProcessTrustedWithOptions
import AppKit                    // NSPasteboard, Process
import Foundation

/// 对应 Python 模块级 _SRC = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
/// .hidSystemState 是 HID 系统级状态，能影响所有 app（包括前台）
private let eventSource = CGEventSource(stateID: .hidSystemState)
```

> **`eventSource` 为何用 Optional 而非 force-unwrap**：`CGEventSource(stateID:)` 是 failable init，理论上极少数情况下返回 nil（系统资源耗尽）。生产代码 guard let 优雅降级，比 `!` 强解更稳。Python `_SRC = CGEventSourceCreate(...)` 在 C 层不返回 nil，但 Swift API 比 C 更严格。

### 1. tap（瞬时击键，对应 Python `send_key` 的非 AppleScript 等价）

**推荐：tap 也走 CGEvent（keydown→立即 keyup）**，跟 hold 走同一路径，省掉 AppleScript+Apple Events。骨架：

```swift
enum KeyInjector {
    /// tap 一个键（可选带单 modifier），瞬时按下立即松开
    /// 对应 Python send_key + hold_down 的"瞬时版"
    static func tap(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
        guard let src = eventSource else { return }
        // keydown 带 flag
        if let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true) {
            down.flags = modifiers                // ← flag 挂在 keydown 上
            down.post(tap: .cghidEventTap)
        }
        // keyup 不带 flag（让系统自动释放 modifier）
        if let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }
}
```

调用：
```swift
// 按 Esc
KeyInjector.tap(virtualKey: CGKeyCode(kVK_Escape))
// 按 Cmd+V（keyCode 9 = kVK_ANSI_V）
KeyInjector.tap(virtualKey: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)
// 按 Ctrl+C
KeyInjector.tap(virtualKey: CGKeyCode(kVK_ANSI_C), modifiers: .maskControl)
```

### 2. hold（按住 N ms 或直到松开，对应 Python `hold_down`/`hold_up`）

**hold 不是"keydown → sleep → keyup"**——那是错的（持续 sleep 模拟按住会触发 key repeat，且占着线程）。**正确语义是：按下时发一次 keydown（带 flag），松开时发 keyup**。中间系统自动维持 modifier 状态（因为没有 keyup，WindowServer 认为键还按着）。这跟 Python `hold_down` / `hold_up` 配对调用语义一致：

```swift
enum KeyInjector {
    /// 按下（key down + 可选 flag），松开时调 release
    /// 对应 Python hold_down —— 按下不松，等用户物理松开触发 release
    static func press(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
        guard let src = eventSource else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true) {
            down.flags = modifiers                // ← flag 挂 keydown（核心坑）
            down.post(tap: .cghidEventTap)
        }
    }

    /// 松开（key up，不带 flag），对应 Python hold_up
    static func release(virtualKey: CGKeyCode) {
        guard let src = eventSource else { return }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) {
            // ★ 不要设 .flags —— 让系统自动释放 modifier
            up.post(tap: .cghidEventTap)
        }
    }
}
```

调用模式：
```swift
// 物理键 k4 配置 option+d hold：串口收到 button down k4 → press，button up k4 → release
// ActionDispatcher:
func onButtonDown(_ cfg: Config) {
    switch (cfg.type, cfg.mode) {
    case ("key", "hold"):
        let (vk, mods) = parseKey(cfg.value)        // "option+d" → (kVK_ANSI_D, .maskAlternate)
        KeyInjector.press(virtualKey: vk, modifiers: mods)
    case ("key", "tap"):
        let (vk, mods) = parseKey(cfg.value)
        KeyInjector.tap(virtualKey: vk, modifiers: mods)
    // ...
    }
}
func onButtonUp(_ cfg: Config) {
    guard cfg.type == "key", cfg.mode == "hold" else { return }
    let (vk, _) = parseKey(cfg.value)
    KeyInjector.release(virtualKey: vk)
}
```

### 3. flags 坑（关键，对应 Python spec 错误写法 vs 正确写法）

**错误写法**（不要这样写，会让 modifier 状态泄漏）：
```swift
// ❌ 禁止：先发 modifier keydown，再发 char keydown（独立 modifier 事件）
let optDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Option), keyDown: true)
optDown?.post(tap: .cghidEventTap)                    // ← 这一行让 WindowServer 以为 Option 一直按着
let dDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_D), keyDown: true)
dDown?.post(tap: .cghidEventTap)
// 即使后面发 Option keyup，char keydown 自己没带 flag，目标 app 看 event-level flags 时丢 modifier
```

**正确写法**（与 Python `hold_down` 1:1 对应）：
```swift
// ✅ 推荐：char keydown 上直接挂 flag
let dDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_D), keyDown: true)
dDown?.flags = .maskAlternate                         // ← flag 直接挂 char keydown
dDown?.post(tap: .cghidEventTap)
```

**modifier flag 枚举映射**（`CGEventFlags`）：

| Python `_FLAG` | Swift `CGEventFlags` | Hex |
|---|---|---|
| `kCGEventFlagMaskCommand` / `cmd` / `command` | `.maskCommand` | `0x100000` |
| `kCGEventFlagMaskShift` / `shift` | `.maskShift` | `0x020000` |
| `kCGEventFlagMaskAlternate` / `option` / `alt` / `opt` | `.maskAlternate` | `0x080000` |
| `kCGEventFlagMaskControl` / `ctrl` / `control` | `.maskControl` | `0x010000` |

注意 `.maskControl` 是 Control 键（不是 right-control 也不是 fn）。`.maskSecondaryFn`（Fn 键，`0x800000`）一般不暴露给上层配置。

---

## Accessibility 权限 Swift 代码骨架

### 弹窗授权（首次启动调用一次）

```swift
import ApplicationServices

enum Accessibility {
    /// 检查并按需弹系统授权对话框
    /// @return true 如果已授权；false 如果未授权（已弹窗提示用户去设置）
    static func ensure() -> Bool {
        if AXIsProcessTrusted() { return true }
        // 弹系统对话框：「打开系统设置」按钮
        // kAXTrustedCheckOptionPrompt = true 让系统自动开 Settings → 隐私 → 辅助功能
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        return false
    }
}
```

要点：
- **`kAXTrustedCheckOptionPrompt`** 是 `Unmanaged<CFBoolean>`，必须 `.takeRetainedValue()` 转成 `CFBoolean`/`NSString` 才能用（每个项目的 Swift 代码都这么写，见 `SoFriendly/2fhey`、`andreasjhkarlsson/mac-dial`、`Pyroh/Fluor`）。
- **调用时机**：app 启动后 menu bar 图标已显示，但用户**第一次**按物理键之前。或者在 `MenuBarExtra` 出现后立即调（不阻塞 UI）。Python 版启动时不主动弹，依赖功能失败静默——Swift 重写主动弹一次更友好。
- **AXIsProcessTrusted() vs AXIsProcessTrustedWithOptions**：前者只查询不弹窗（用于运行时检查「现在有没有授权」）；后者带 prompt 参数才弹。两者都从 `ApplicationServices` 来。
- **无需 info.plist 加 NSAppleEventsUsageDescription**：那是 AppleScript/Apple Events 用的（Python `osascript` 那条路径需要）。**纯 CGEvent 注入不需要任何 usage description**——CGEvent 走 HID 层不走 Apple Events。
- **现有 `project.yml` 里 `NSAppleEventsUsageDescription` 可以删**（如果阶段 C 决定 tap 也走 CGEvent 而非 AppleScript，见 spec 冲突章节）。**保留也没害**，未来如果要 AppleScript 自动化（如打开 System Settings）还是需要。

### 权限被拒的降级（Python spec 的「容错哲学」复刻）

- 检测：`AXIsProcessTrusted()` 在每次按键前快速查询（开销极低，纳秒级）。
- 降级：未授权时**只打日志 + 菜单栏图标加红点提示**，不崩、不弹窗（首次已弹过）。对应 Python 「功能静默失效 + HAS_CGEVENT flag」语义。
- 实测：未授权时 `CGEvent.post` 调用不会崩，但目标 app 收不到事件——所以加 menu bar 图标状态指示比 `print` 更友好。

---

## Sandbox vs CGEvent 结论（阶段 C gating 决策）

### 一句话结论

**保留 sandbox（`com.apple.security.app-sandbox = true`），不动任何 entitlement，CGEvent `.post(tap: .cghidEventTap)` 完全可用，唯一前置是 Accessibility 权限（TCC，运行时用户授权，不是 entitlement）。**

### 直接证据

| 来源 | sandbox 状态 | CGEvent 注入 | 结论 |
|---|---|---|---|
| **`eddmann/ClipVault` `ClipVault.entitlements`** | `app-sandbox = true` + 仅 `files.user-selected.read-only`，**无任何临时例外** | `PasteHelper.swift:synthesizeCommandV()` 用 `CGEvent(...).flags = .maskCommand; .post(tap: .cghidEventTap)` 实测注入 Cmd+V | **沙盒下 CGEvent 注入完全可用**，只需 Accessibility TCC |
| **`shivadharmi/CHIMERA` `KeystrokeInjector.swift`** | N/A（red-team 工具，明确关沙盒） | 完整 `postChord` 实现，注释详尽记录了 flag 时序与多 modifier 坑 | 多 modifier 时纯 `.flags` 有残留问题；单 modifier 安全 |
| **`andreasjhkarlsson/mac-dial` `MacDial.entitlements`** | `app-sandbox = false` | 用 `CGEvent(mouseEventSource:...)` 发鼠标事件 | 显式关沙盒，但**原因不是 CGEvent**（mac-dial 还访问 IOKit 设备） |
| **`mickael-menu/ShadowVim` `ShadowVim.entitlements`** | `app-sandbox = false` | CGEvent + AXUIElement 大量注入 | 关沙盒因为需要 Vim 进程间通信，**不是** CGEvent 限制 |
| **`MatthiasGrandl/Loungy` `entitlements.plist`** | `app-sandbox = false` + `accessibility = true` | launcher 类应用 | 关沙盒是为了全局快捷键 + 多 app 通信 |

### 推理

CGEvent 的 `.post(tap: .cghidEventTap)` 调用的是 WindowServer 的 HID 事件注入路径，**不是** Mach service lookup（不通过 bootstrap port 找 `com.apple.windowserver`）。App Sandbox 限制的是：
- 文件系统路径访问
- 网络（出站连接需 entitlement）
- Mach lookups（除白名单）
- 设备访问（USB、串口、摄像头等需 entitlement）

CGEvent post **不在这四类限制里**——它通过 `CGSSetEfficaciousAccess` / HID 系统调用直接走，sandbox 不拦截。**Accessibility TCC** 是用户级隐私授权（系统设置 → 隐私与安全 → 辅助功能），独立于 sandbox。ClipVault 是 App Store 上架的 sandboxed app，它的存在就是反例证明。

### 不需要做的事

- ❌ 不要加 `com.apple.security.temporary-exception.mach-lookup-name` —— 跟 CGEvent 无关。
- ❌ 不要关 `app-sandbox` —— 阶段 B 已经开 sandbox + serial entitlement，关掉会破坏串口配置。
- ❌ 不要加 `com.apple.security.accessibility` —— 这**不是**真正的 accessibility entitlement（Mac App Store 拒绝带这个 key 的提交，accessibility 权限只能用户在 System Settings 手动给，不能 entitlement 声明）。Loungy 带 `accessibility = true` 是因为它**不上 App Store**（个人分发的 launcher）。本项目未来上 App Store 就不能加这个 key。
- ❌ 不要加 `com.apple.security.device.input` —— 不存在的 entitlement。

### 需要做的事

1. **保留阶段 B 的 entitlements 不变**（`app-sandbox = true` + `device.serial = true`）。
2. **首次启动调 `Accessibility.ensure()`** 弹 System Settings 对话框。
3. **README 写明**：「首次运行需在系统设置 → 隐私与安全 → 辅助功能中允许 VibeBoard」（对应 Python 版 docstring `:14-15`）。

---

## cmd 动作 Swift 骨架（对应 Python `run_cmd`）

```swift
import Foundation

enum CmdRunner {
    /// 异步执行 shell 命令，不阻塞调用线程（对应 Python subprocess.Popen）
    /// @param cmd shell 命令字符串，如 "open -a Codex"
    static func run(_ cmd: String) {
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", cmd]
        p.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        p.standardError = FileHandle(forWritingAtPath: "/dev/null")
        // run() 异步启动后立即返回（对应 Popen），不调 waitUntilExit
        do {
            try p.run()
        } catch {
            NSLog("[VibeBoard] cmd 执行失败: \(cmd) — \(error.localizedDescription)")
        }
    }
}
```

要点：
- **`Process.run()` 是非阻塞的**（启动后立即返回，进程异步跑）—— 等价 Python `subprocess.Popen(...)`。**不要**调 `p.waitUntilExit()`（阻塞，会卡串口线程）。
- **shell 解释器**：用 `/bin/sh -c <cmd>`（不是 `/bin/bash`），让用户配置里的 shell 命令（`open -a Codex`、`osascript -e '...'` 等）按 macOS 默认 shell 解释。对应 Python `shlex.split` + 直接 exec——但 Swift 走 `/bin/sh -c` 比 Swift 手写 shlex 简单且更兼容（支持管道、引号、env 展开）。
- **错误吞掉**：`try? p.run()` 或 catch + log，**永远不抛**到串口线程（spec「守护进程不崩」）。
- **sandbox 限制**：sandbox 下 `Process.run("/bin/sh", "-c", ...)` 默认**只能执行** `/usr/bin` 和 `/bin` 下的系统二进制（这是 sandbox 默认行为）。用户配置 `open -a Codex`（`/usr/bin/open`）✅；配置自定义脚本（如 `/Users/me/foo.sh`）❌。**这是阶段 C 的潜在限制**，需要写入 README 或测试验证。Python 版无此限制（无沙盒）。如果实测发现用户常用脚本路径被拒，可能需要 `com.apple.security.temporary-exception.files.absolute-path.*` 例外，但**不要预防性加**。

---

## text 动作 Swift 骨架（对应 Python `send_text`）

```swift
import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum TextInjector {
    /// 把文本写入剪贴板并合成 Cmd+V，可选末尾回车
    /// 对应 Python send_text —— 绕过输入法，对中文最可靠
    /// @param text 要输入的文本
    /// @param enter 是否末尾补 Enter（默认 true）
    static func inject(_ text: String, enter: Bool = true) {
        // 1. 写剪贴板
        let pb = NSPasteboard.general
        pb.clearContents()                              // ← 必须先 clearContents 再 setString
        pb.setString(text, forType: .string)

        // 2. 发 Cmd+V（keyCode 9 = kVK_ANSI_V）
        KeyInjector.tap(virtualKey: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)

        // 3. 可选 Enter，等待 paste 事件落地（对应 Python sleep(0.05)）
        if enter {
            Thread.sleep(forTimeInterval: 0.05)
            KeyInjector.tap(virtualKey: CGKeyCode(kVK_Return))
        }
    }
}
```

要点：
- **`clearContents()` 必须先调**（每次 paste 前清空旧内容）。Python 用 `subprocess.run(["pbcopy"], input=text.encode())` 隐式覆盖；Swift `NSPasteboard.general` 不 clear 直接 setString 会**追加**而不是替换。
- **覆盖剪贴板是已知副作用**（spec「不保存/恢复原剪贴板」）——刻意不做，时序复杂。
- **`Thread.sleep(0.05)` vs `DispatchQueue.main.asyncAfter`**：Python 是同步 `time.sleep(0.05)`，Swift 在后台线程跑（CGEvent 注入建议 dispatch 到 global queue）就用 `Thread.sleep`，主线程跑就 `asyncAfter`。0.05s 是 paste 事件落地的经验值，对齐 Python。
- **sandbox 下 NSPasteboard.general 完全可用**（ClipVault 实证）——`NSPasteboard` 不受 sandbox 限制，它是进程间通信的标准机制。
- **中文输入**：`pb.setString(text, forType: .string)` 直接放 UTF-8 字符串，Cmd+V 粘贴原字符，**绕过输入法**（这是 Python 选剪贴板方案的核心原因）。Swift 完全沿用此设计。

---

## key code 查询方法 + 常用键码表

### 方法 1：Carbon `kVK_ANSI_*` 符号常量（推荐）

```swift
import Carbon.HIToolbox

let keyCode = CGKeyCode(kVK_ANSI_A)   // 0x00 = 0
```

常量定义在 SDK 头文件 `/Applications/Xcode.app/.../MacOSX26.5.sdk/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/Events.h`（已在本机确认，macOS 26.5 SDK 完整存在）。`import Carbon.HIToolbox` 只 link HIToolbox 子框架，不会拉整个 Carbon。

### 方法 2：硬编码数字表（不推荐，仅参考）

仅当 import Carbon 有特殊困难时用。对照 Python `vibe_control.py:73-79` 的 `CHAR_CODES`：

| 字符 | `kVK_ANSI_*` | hex | dec |
|---|---|---|---|
| a | `kVK_ANSI_A` | 0x00 | 0 |
| s | `kVK_ANSI_S` | 0x01 | 1 |
| d | `kVK_ANSI_D` | 0x02 | 2 |
| f | `kVK_ANSI_F` | 0x03 | 3 |
| h | `kVK_ANSI_H` | 0x04 | 4 |
| g | `kVK_ANSI_G` | 0x05 | 5 |
| z | `kVK_ANSI_Z` | 0x06 | 6 |
| x | `kVK_ANSI_X` | 0x07 | 7 |
| c | `kVK_ANSI_C` | 0x08 | 8 |
| v | `kVK_ANSI_V` | 0x09 | 9 |
| b | `kVK_ANSI_B` | 0x0B | 11 |
| q | `kVK_ANSI_Q` | 0x0C | 12 |
| w | `kVK_ANSI_W` | 0x0D | 13 |
| e | `kVK_ANSI_E` | 0x0E | 14 |
| r | `kVK_ANSI_R` | 0x0F | 15 |
| y | `kVK_ANSI_Y` | 0x10 | 16 |
| t | `kVK_ANSI_T` | 0x11 | 17 |
| 1-0 | `kVK_ANSI_1`..`kVK_ANSI_0` | 0x12-0x1D | 18-29（不连续） |

**特殊键 / 修饰键**（对照 Python `KEY_CODES`、`MOD_CODES`）：

| 名 | 常量 | hex | dec |
|---|---|---|---|
| esc | `kVK_Escape` | 0x35 | 53 |
| tab | `kVK_Tab` | 0x30 | 48 |
| return/enter | `kVK_Return` | 0x24 | 36 |
| space | `kVK_Space` | 0x31 | 49 |
| delete (backspace) | `kVK_Delete` | 0x33 | 51 |
| ↑ | `kVK_UpArrow` | 0x7E | 126 |
| ↓ | `kVK_DownArrow` | 0x7D | 125 |
| ← | `kVK_LeftArrow` | 0x7B | 123 |
| → | `kVK_RightArrow` | 0x7C | 124 |
| cmd | `kVK_Command` | 0x37 | 55 |
| shift | `kVK_Shift` | 0x38 | 56 |
| opt/alt | `kVK_Option` | 0x3A | 58 |
| ctrl | `kVK_Control` | 0x3B | 59 |

> Python `KEY_CODES`/`CHAR_CODES` 表是硬编码数字，Swift 改用 `kVK_ANSI_*` 符号常量，可读性更好且 layout-changed 时 Apple 会更新头文件。**但请注意**：`kVK_ANSI_*` 是 **US QWERTY 布局** 的物理键位 —— 用户用 Dvorak/French 布局时，物理同一个键的 char 不同但 keyCode 一样（这是 macOS HID 设计：virtualKey 是物理位置，char 是 layout 映射）。Python 版同样基于 US 布局表，Swift 沿用一致。

### 方法 3：运行时查询（不在阶段 C 范围）

如果未来需要支持任意字符（如配置 `key = "ñ"`），用 `UCKeyTranslate()` 从键盘 layout 动态查 char→keyCode。复杂、不在阶段 C 范围。**当前需求只覆盖 Python `CHAR_CODES`/`KEY_CODES` 表内的字符**，硬编码 + kVK 常量已足够。

---

## Spec 冲突处理

### 冲突 1：tap 与 hold 不可混（quality-guidelines.md:43）

**Spec 原文**：「tap 走 `send_key`（osascript `keystroke`），hold 走 `hold_down`/`hold_up`（CGEvent）。在 `fire_down` 里按 `mode` 二选一，不要让 tap 路径调 CGEvent 或反之。」

**Swift 重写建议**（按规则 7「暴露冲突不折中」）：选 **tap 也走 CGEvent**（合并到一条注入路径），理由：
1. Python 用 osascript 是历史包袱（早期只用 keystroke，后来才加 CGEvent hold）。
2. Swift 重写时合并到 CGEvent 一条路径，少维护一份 AppleScript 代码 + 少一个 Apple Events 授权依赖（去掉 `NSAppleEventsUsageDescription`）。
3. 行为差异：CGEvent 走 HID 层，对所有前台 app 一致；`osascript keystroke` 走 Apple Events + System Events 转发，对某些 Electron app（VS Code 等）有时不触发。CGEvent 更可靠。
4. CHIMERA、ClipVault、MacDial 全用 CGEvent 不用 AppleScript，是 Swift 圈共识。

**对应 spec 改动**（不在本调研范围，是后续 spec update 工作）：把 `quality-guidelines.md:43` 改成「tap 与 hold 都走 CGEvent，二选一靠 mode（瞬时 vs 长按）；不再用 osascript」。

### 冲突 2：`NSAppleEventsUsageDescription` 是否需要

现有 `project.yml` 已加 `NSAppleEventsUsageDescription`（阶段 A），原意是 Python 版用 osascript 的 cmd 动作。如果阶段 C 决定 cmd 走 `Process` + `/bin/sh`（不走 osascript），并且 tap 走 CGEvent（不走 AppleScript），则 **`NSAppleEventsUsageDescription` 不再需要**，可以删。但**保留也没害**（未来若果要发 Apple Event 控制 System Settings 等）。**决策：保留不动**（spec「外科手术式修改」，删 plist key 不是阶段 C 的核心工作）。

---

## 已知坑（按优先级）

### 1. flags 必须挂 char keydown，不能单独发 modifier keydown（最重要）

见上面「flags 坑」专节。Spec 已强制，CHIMERA `postChord` 注释也记录了多 modifier 残留问题。**单 modifier 场景（本项目当前支持范围）纯 `.flags` 安全**。

### 2. CGEventSource 用 `.hidSystemState`，不用 `.privateState`

`.hidSystemState` 影响系统全局 HID 状态（所有 app 能感知），`.privateState` 只影响本进程（注入到前台 app 不生效）。Python `kCGEventSourceStateHIDSystemState` 是对的，Swift 同名。

### 3. Accessibility 权限被撤销/未授权的静默失效

未授权时 `CGEvent.post` 调用不抛错也不崩，但目标 app 收不到事件。Python 用 `HAS_CGEVENT` flag + log 警告；Swift 等价是每次按键前 `AXIsProcessTrusted()` 检查 + menu bar 图标状态指示（红点）。

### 4. 线程模型：CGEvent.post 可以在任意线程

不像 UI 操作必须在主线程，`CGEvent.post` 没有线程绑定。但建议在 **ORSSerialPort delegate 回调（main queue）dispatch 到 global queue** 后调（避免阻塞主线程画 menu），见 `orsserialport.md:282-288` 已记录的指引。

### 5. Process.run 在 sandbox 下受限于系统二进制

sandboxed app 用 `Process.run("/bin/sh", ...)` 默认只能 exec `/bin`、`/usr/bin` 下的二进制。用户配置自定义脚本路径会被拒。**这是已知限制**，写入 README 提示用户。不预防性加 entitlement。

### 6. NSPasteboard.clearContents() 必须先调

直接 `setString` 不 clearContents 会追加而不是替换。每次 `TextInjector.inject` 都 `clearContents()` + `setString`。

### 7. kAXTrustedCheckOptionPrompt 的 .takeRetainedValue()

`kAXTrustedCheckOptionPrompt` 是 `Unmanaged<CFString>`，必须 `.takeRetainedValue()` 才能用，否则运行时 crash。每个 Swift 项目的写法都一致（`mac-dial`、`2fhey`、`Fluor`）。

### 8. 多 modifier 组合（ctrl+shift+d 等）暂不支持

Python `hold_down` 的 `key.split("+", 1)` + 单 `_FLAG` 限制只支持 `mod+key`。Swift 沿用此限制。多 modifier 是后续扩展（spec `quality-guidelines.md:65` 已记录），不在阶段 C 范围。如果未来需要，按 CHIMERA `postChord` 的「显式 modifier keydown + flags + modifier keyup」模式实现，不要继续用纯 `.flags`。

### 9. CGEvent 初始化返回 Optional，必须 guard let

`CGEvent(keyboardEventSource:virtualKey:keyDown:)` 是 failable init（系统资源不足时返回 nil）。所有调用必须 `if let down = CGEvent(...) { ... }` guard，不要 `!` 强解。

---

## 来源引用

### 一手源（已读）

- **本机 macOS 26.5 SDK** `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/Events.h`
  - `kVK_ANSI_*` 常量列表（`:197-265`）
  - modifier + 特殊键常量（`:266-275`）：`kVK_Return=0x24, kVK_Tab=0x30, kVK_Space=0x31, kVK_Delete=0x33, kVK_Escape=0x35, kVK_Command=0x37, kVK_Shift=0x38, kVK_Option=0x3A, kVK_Control=0x3B`
- **本仓库 Python 蓝本** `/Users/ethereal/Documents/Code/openvibeboard/vibe_control.py`：
  - `_post` helper `:48-52`（CGEventSetFlags 调用时机）
  - `hold_down` `:150-161`（flags 挂 char keydown）
  - `hold_up` `:164-172`（keyup 不带 flag）
  - `_FLAG` map `:43-46`（modifier → flag 映射）
  - `KEY_CODES`/`CHAR_CODES`/`MOD_CODES` `:67-79`（keycode 查表）
  - `send_text` `:131-141`（pbcopy + Cmd+V 方案 + sleep 时序）
  - `run_cmd` `:106-108`（subprocess.Popen 非阻塞）
  - `fire_down`/`fire_up` `:175-206`（动作分发链）

### GitHub Swift CGEvent 项目取证（5 个，按权威度排序）

- **`eddmann/ClipVault`** —— sandboxed App Store app 用 CGEvent 发 Cmd+V 的**直接证据**：
  - `ClipVault/ClipVault.entitlements`（只有 `app-sandbox + files.user-selected`，无临时例外）
  - `ClipVault/PasteHelper.swift:synthesizeCommandV()`（用 `.flags = .maskCommand` + `.post(tap: .cghidEventTap)`）
- **`shivadharmi/CHIMERA` `agent/chimera-mac-agent/Sources/ChimeraMacAgent/Capabilities/KeystrokeInjector.swift`**：
  - `postChord` `:350-385`（modifier keydown + char keydown flags + modifier keyup 三段式，多 modifier 残留坑注释详尽）
  - `flagsFor` `:328-335`（modifier mask → CGEventFlags 映射）
  - `asciiKeyMap` `:218-272`（kVK_ANSI_* → 字符表，含 shift 二级映射）
  - `writeTextToPasteboardAndSavePrior`（NSPasteboard clearContents + setString + 剪贴板备份恢复模式）
  - `AXIsProcessTrusted` 检查 `:71-77`
- **`andreasjhkarlsson/mac-dial` `MacDial/AppDelegate.swift`**：
  - `requestPermissions()` `:14-27`（`kAXTrustedCheckOptionPrompt.takeRetainedValue()` 标准写法）
  - `MacDial/MacDial.entitlements`（`app-sandbox = false`，但**原因不是 CGEvent**——它要访问 IOKit 物理设备）
- **`SoFriendly/2fhey` `TwoFHey/Permission.swift`**：5 行最简 AXIsProcessTrustedWithOptions 实现
- **`MatthiasGrandl/Loungy` `macos/entitlements.plist`**：`app-sandbox = false` + `accessibility = true` 的非沙盒 launcher 模板

### 本仓库内部参考

- `.trellis/spec/backend/quality-guidelines.md:7-32` —— CGEvent flags 坑 spec（跨语言约束，必读）
- `.trellis/spec/backend/directory-structure.md` —— 动作分发链（cmd→Process / key→tap|hold / text→剪贴板）
- `.trellis/tasks/07-04-swift-menubar-app/research/orsserialport.md` —— 阶段 B 已建立的 sandbox + serial entitlement 背景（CGEvent 沿用同一 sandbox 配置）
- `project.yml`（当前 XcodeGen 配置，含 `NSAppleEventsUsageDescription` 与阶段 B 加的 entitlement）
- `VibeBoard/VibeBoard.entitlements`（阶段 B 已加 `app-sandbox + device.serial`，CGEvent 不需改）
- `.trellis/tasks/07-04-swift-menubar-app/implement.md` —— 阶段 C 任务定义

---

## Caveats / Not Found

- **未真机验证**：所有结论基于 5 个 GitHub 项目静态取证 + SDK 头文件 + spec 文档分析。ClipVault 是 sandboxed+CGEvent 的反例证明，但本项目（VibeBoard）的具体组合（sandbox + serial + menu bar app + CGEvent tap/hold/text）的端到端实测，留到 implement 阶段跑 `xcodegen generate && xcodebuild` + 真机按键触发。
- **context7 MCP 未返回有效结果**：`CoreGraphics`、`Quartz`、`CGEvent` 都是 Apple 系统框架（不是 SPM 包），context7 索引不到。改用本机 SDK header + GitHub 真实项目取证，结论反而更权威（一手源码 vs 二手索引）。
- **sandbox 下 Process.run 二进制路径白名单的具体清单未深查**：Apple 文档表述「sandbox restricts executable to system binaries」但没给完整白名单。实测路径如 `/usr/bin/open`、`/bin/sh` 安全；自定义脚本路径（`~/foo.sh`）需要测试。建议阶段 C 实现后用 cmd 动作配置几种典型命令验证。
- **多 modifier 组合（ctrl+shift+d）未在 Swift 实现里验证**：当前 spec 只支持单 modifier，CHIMERA `postChord` 是参考但本项目不实现。如果未来扩展，需要重写 `KeyInjector.press`/`release` 走显式 modifier keydown 路径。
- **上 App Store 的可行性未评估**：本调研聚焦技术实现。CGEvent 注入功能上 App Store 需要审查（Accessibility 用途声明、用户协议条款等），是后续分发决策。ClipVault 上架成功说明同类功能能过审，但 VibeBoard 的具体定位（远程键盘、自动化）可能触发额外审查。

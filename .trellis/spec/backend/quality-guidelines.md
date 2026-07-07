# 质量约定（含 CGEvent 核心坑）

> 这里是本项目最容易踩坑的地方。改 `KeyInjector.press/release` / `ActionDispatcher.decideAction` 之前必读。

---

## ⚠ CGEvent hold 的 modifier flag 坑（最重要，跨语言硬约束）

**组合键 hold 时，modifier flag 必须直接挂在 char keydown 上，不要单独发 modifier 的 keydown/up。**

这条坑 v0.1 用 Python + pyobjc 踩过，Swift 重写时逐行复刻。违反会导致 modifier 状态丢失/残留，并触发字符 repeat。

Swift 正确写法（`KeyInjector.press`，`Key/KeyInjector.swift`）：
```swift
static func press(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
    guard let src = eventSource else { return }
    if let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true) {
        down.flags = modifiers          // ★ flag 挂 keydown（核心坑）
        down.post(tap: .cghidEventTap)
    }
    // 不发 keyup —— WindowServer 没收到 keyup 就认为键还按着，自动维持 modifier 状态。
    // 用户松开物理键时由 ActionDispatcher 调 KeyInjector.release 配对。
}
```

`release` 只发 char keyup（**不**带 flag），让系统自动释放 modifier（`Key/KeyInjector.swift`）：
```swift
static func release(virtualKey: CGKeyCode) {
    guard let src = eventSource else { return }
    if let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) {
        // ★ 不要设 .flags——让系统自动释放 modifier
        up.post(tap: .cghidEventTap)
    }
}
```

**原因**：CGEvent 的 modifier 是 keydown 的 `flags` 属性，不是独立的键状态。分开发（先发 modifier keydown，再发 char keydown）会破坏 WindowServer 对 modifier 的状态跟踪，导致组合键只打出单字符或卡住。

**tap 路径同样适用**：`KeyInjector.tap` 的 keydown 挂 flag、keyup 不带 flag（瞬时击键，与 press/release 同源约束）。

v0.1 Python 的对照实现见 `archive/python-v0.1/vibe_control.py` 的 `hold_down`/`hold_up`，语义 1:1。

---

## 必须遵守

### ConfigStore actor 串行化配置读写

v0.1 用 `threading.Lock`（`CONFIG_LOCK`）保护 `CONFIG` 全局字典。Swift 用 `actor ConfigStore` 串行化——所有读写经 actor，编译器保证无数据竞争。

```swift
// 读（ActionDispatcher.handle，跨 actor await）
let cfg = await ConfigStore.shared.snapshot()[event.button]

// 写（KeyMappingsView.save，跨 actor await）
await ConfigStore.shared.save(localConfig)
```

**禁止**：直接持有 `ConfigStore` 的内部 `config` 字典引用绕过 actor。`snapshot()` 返回的是值拷贝，调用方持有的是不可变快照。

### tap 与 hold 不可混（按 mode 分发）

`ActionDispatcher.decideAction` 按 `cfg.mode` 二选一：
- `mode == "hold"` → `pressKey` / `releaseKey`（CGEvent keydown 等 keyup）
- `mode == "tap"` 或未指定 → `tapKey`（CGEvent keydown 立即 keyup）

不要让 tap 路径调 `press`（会卡住等待永不来的 release），反之亦然。

> 与 v0.1 的有意偏离：v0.1 的 tap 走 `osascript keystroke`（Apple Events），hold 走 CGEvent；Swift 把 tap 也合并到 CGEvent 一条注入路径（主会话裁决，简化 + 统一 flags 处理）。spec 字面「tap 走 osascript」是 Python 历史包袱，Swift 不沿用。

### 单 modifier 限制

`KeyInjector.parseKey` 用 `key.firstIndex(of: "+")` 拆第一个 `+`，只支持 `mod+key`（如 `option+d`）。多 modifier（如 `ctrl+shift+d`）是后续扩展，当前会返回 nil（charStr=`shift+d` 查不到 keycode）。

Settings 录制也对齐此限制——只生成单 modifier 描述。

---

## 文本输入动作（type == "text"）

`TextInjector.inject`（`Actions/ActionDispatcher.swift`）用**剪贴板方案**，不用 osascript `keystroke`：

```swift
static func inject(_ text: String, enter: Bool = true) {
    let pb = NSPasteboard.general
    pb.clearContents()                  // 必须先 clear 再 set，否则追加而非替换
    pb.setString(text, forType: .string)

    KeyInjector.tap(virtualKey: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)  // Cmd+V

    if enter {
        Thread.sleep(forTimeInterval: 0.05)   // 等 paste 事件落地，避免与 enter 重叠
        KeyInjector.tap(virtualKey: CGKeyCode(kVK_Return))
    }
}
```

- **为什么不用 keystroke**：`keystroke "继续"` 依赖当前输入法，中文模式下可能触发拼音输入。`NSPasteboard` + `Cmd+V` 直接粘贴字符，绕过输入法，对中文最可靠。
- **副作用**：覆盖一次剪贴板内容。快捷键场景可接受（用户专为输入这段文字才按这个键）。不保存/恢复原剪贴板（时序复杂，刻意不做）。
- **时序**：`clearContents` + `setString`（同步）→ `Cmd+V` → 若 enter，`sleep(0.05)` 后再发 enter。`sleep(0.05)` 对齐 v0.1 的 `time.sleep(0.05)`。
- **与 v0.1 的差异**：v0.1 用 `subprocess.run(["pbcopy"])` 写剪贴板；Swift 用 `NSPasteboard.general` 直接写，更干净（不 fork 进程）。

---

## 权限前置（运行时，非代码）

启动前必须授权，否则功能静默失效。这些写在 `OpenVibeBoardApp.init`（启动时 `Accessibility.ensure()` 弹一次系统对话框）+ `MenuBarView`（未授权时红色提示 + 重新请求按钮）：

- **辅助功能（Accessibility）** —— 系统设置 → 隐私与安全性 → 辅助功能。CGEvent 注入的唯一前置。
  - 未授权时 `ActionDispatcher.handle` 守门：`guard Accessibility.isTrusted else { log + return }`，不发任何 CGEvent。
  - 检查用 `AXIsProcessTrusted()`（纳秒级，每次按键前调）；请求弹窗用 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`。
- **串口** —— sandboxed app 需 `com.apple.security.device.serial` entitlement（`OpenVibeBoard.entitlements` 已声明）+ ad-hoc 签名（`CODE_SIGN_IDENTITY: "-"`）。缺 entitlement → `serialPort(_:didEncounterError:)` 收到 EPERM(1)。
- **⚠ 退出占用串口的其他进程** —— 旧的 v0.1 Python 客户端（`vibe_control.py`）、其他串口工具（screen / Arduino IDE）开着 `/dev/cu.usbmodem3101` 会导致 EBUSY(16)。启动 app 前确认释放。

> 与 v0.1 的差异：v0.1 的 tap 走 osascript 需「自动化」授权（System Events），hold 走 CGEvent 需「辅助功能」。Swift 把 tap 也合并到 CGEvent，所以**只需辅助功能一项授权**，不再需要「自动化」。

---

## 四动作实测门（权威验证）

CGEvent / Process / NSPasteboard 的副作用无法用单元测试覆盖（见 `error-handling.md` 的「不测」清单）。**改 `KeyInjector` / `ActionDispatcher` / `CmdRunner` / `TextInjector` 后，必须手动回归四种动作**：

| 键 | type | mode | value | 验证 |
|----|------|------|-------|------|
| k1 | cmd | tap | `open -a Codex` | 按下 → Codex app 被打开（CmdRunner.run / Process 非阻塞） |
| k2 | text | - | `继续`（enter: true） | 按下 → 焦点输入框出现「继续」+ 回车（NSPasteboard + Cmd+V + Enter） |
| k3 | key | tap | `ctrl+c` | 按下 → 中断前台进程（CGEvent keydown 立即 keyup） |
| k4 | key | hold | `option+d` | **按下不松** → 系统持续识别 modifier 状态（如触发语音听写）；**松开** → 干净释放，无残留 |

**k4 是核心硬门**：组合键 hold 必须验证「按下不松 → 持续 modifier → 松开干净释放」。这是 flags 坑的直接验证——违反 flags 约束的代码会在这里露馅（只打出单字符 / 卡住 / modifier 残留影响下一次按键）。

阶段 F 的 `decideAction` 纯函数重构**行为不变**：分支语义 1:1 对照原 `fireDown`/`fireUp`，实测门仍是权威，单元测试只覆盖纯决策逻辑。

---

## 禁止模式

- ❌ **绕过分发链**。在 `SerialMonitor` 或 delegate 里直接调 `KeyInjector.tap` / `Process.run` / `NSPasteboard`。所有动作必须经 `ActionDispatcher.handle` → `decideAction` → 执行，方便统一加日志、权限检查、dispatch。
- ❌ **用阻塞 API 执行 cmd 动作**。`CmdRunner.run` 调 `Process.run()`（异步启动后立即返回，等价 v0.1 的 `subprocess.Popen`），**不**调 `waitUntilExit()`（会卡 main queue / 串口回调链）。
- ❌ **在 keyup 上挂 modifier flag**（见上面 flags 坑）。`release` 必须不带 flag。
- ❌ **缓存 `SMAppService.mainApp.status`**。用户随时能在系统设置改登录项，缓存会显示陈旧勾选态。`LaunchAtLogin.isEnabled` 每次调用都重读。
- ❌ **缓存 `Accessibility.isTrusted`**。用户随时能在系统设置改授权，每次按键前重读。
- ❌ **`print` 到 stdout 而不走 stderr 包装**（见 logging-guidelines）。menu bar app 的 stdout 可能被 buffer，stderr 立即可见。

---

## 测试与验证

**单元测试**（`OpenVibeBoardTests/`，Swift Testing）：测纯逻辑——`KeyInjector.parseKey`（参数化覆盖单 modifier / 别名 / 特殊键 / 非法 / 多 modifier 不支持）、`KeyConfig`/`Config` Codable（v0.1 schema 兼容往返）、`defaultConfig`（守护 k1-k4 迁移意图）、`ConfigStore`（注入 URL 测 load/save/幂等）、`SerialMonitor.parseLine`（button down/up kN + 非法）、`ActionDispatcher.decideAction`（全分支参数化）。

**不测**（实测门覆盖）：`KeyInjector.tap/press/release`（CGEvent 副作用）、`CmdRunner.run`（Process）、`TextInjector.inject`（NSPasteboard + CGEvent）、`LaunchAtLogin`（SMAppService 系统状态）、`SerialMonitor` 端口/重连/delegate（ORSSerialPort + 硬件）——这些由四动作实测门覆盖。

**手动验证步骤**：
1. `xcodegen generate` + `xcodebuild ... build` 构建出 `OpenVibeBoard.app`。
2. 确认已退出占用串口的其他进程（v0.1 Python 客户端 / screen / Arduino IDE）。
3. `open .../OpenVibeBoard.app`，状态栏出现键盘图标。
4. 首启弹辅助功能授权对话框 → 系统设置授权 OpenVibeBoard。
5. 菜单栏图标点开 → 看串口状态「已连接」+ 最近事件。
6. Settings（⌘, 或菜单「打开设置…」）改配置保存 → 看日志「配置已保存并热生效」。
7. 按物理键验证 k1/k2/k3/k4 四种动作（见上面实测门表）。

涉及 CGEvent 的改动，**必须**测 k4（hold 组合键）：按下不松 → 持续 modifier → 松开干净释放，无残留。

---

## 编码风格

- 中文注释（与现有代码一致，对齐 v0.1）。
- 类型/方法名 PascalCase / camelCase（Swift 惯例）；常量 `static let`（如 `SerialMonitor.path` / `baudRate`）。
- virtual key code 用 Carbon `kVK_ANSI_*` 符号常量（`Carbon.HIToolbox`），**不**硬编码 magic number。v0.1 Python 用硬编码数字表（`KEY_CODES`/`CHAR_CODES`），Swift 升级为符号常量。
- `enum` + `static` 方法封装无状态能力（`KeyInjector` / `CmdRunner` / `TextInjector` / `Accessibility` / `LaunchAtLogin`），对齐 Swift 习惯（无实例状态的命名空间）。
- `@MainActor` 标注 UI / ObservableObject（`SerialMonitor` / `ActionDispatcher`）；`nonisolated static` 标注纯函数（`parseLine` / `decideAction` / `parseKey` / `label`），让测试在 nonisolated 上下文直接调。

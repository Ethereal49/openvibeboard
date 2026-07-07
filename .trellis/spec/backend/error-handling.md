# 错误处理

> 守护进程优先「不崩」+ 权限/资源缺失静默降级。不定义自定义异常类（这个规模不需要，Swift 用 `throws` + `try?` + `guard let` 足够）。

---

## 守护进程不崩

### 串口：错误码分流 + 自动重连

`SerialMonitor` 的 `ORSSerialPortDelegate.serialPort(_:didEncounterError:)` 是所有串口错误的统一入口（open 失败 / read 出错 / ioctl 出错，`NSPOSIXErrorDomain`）。收到后**不崩**：打日志 + 关端口 + 5 秒后自动重连。

错误码语义（`Serial/SerialMonitor.swift`）：
- **EPERM(1)** —— entitlement 缺（`com.apple.security.device.serial` 没加 / sandbox 未签名）。重连也修不了，但仍安排重连（用户改完 entitlement 后无需重启 app，代价是日志会刷，可接受）。
- **EBUSY(16)** —— 端口被占（旧版 v0.1 Python 客户端 / screen / Arduino IDE 开着）。等 5 秒重试，等占用方退出。
- **ENXIO(6)** —— 设备已拔，`serialPortWasRemovedFromSystem` 也会来。
- **ENOENT(2)** —— 路径不存在（`ORSSerialPort(path:)` 返回 nil 时在 `openPort` 里直接 scheduleReconnect，不走 delegate）。

```swift
@objc func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
    let nsError = error as NSError
    let msg = "串口错误: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)"
    log("⚠️ \(msg)")
    lastError = msg
    status = .error
    port?.close()
    port = nil
    scheduleReconnect()   // 固定 5 秒，避免 spin
}
```

`serialPortWasRemovedFromSystem`（USB-CDC 设备拔掉）同样只 log + 重连，不让 app 死。

> 对齐 v0.1：v0.1 的 `serial_loop` 外层 `try/except serial.SerialException` 只 log 不让线程死掉（影响 HTTP 服务）。Swift 的 SerialMonitor 是 `@MainActor` ObservableObject，串口错误只影响串口功能，MenuBarExtra/Settings 不受影响。

### 配置 IO：try? 吞错

`ConfigStore` 的所有磁盘操作用 `try?` 吞错（`Models/Config.swift`）：
```swift
if let data = try? Data(contentsOf: url),
   let decoded = try? JSONDecoder().decode(Config.self, from: data) {
    config = decoded       // 正常路径
} else {
    config = defaultConfig  // 文件不存在/损坏 → 写默认配置
    persist()
}
```

- 读失败（文件不存在/损坏/JSON 解析失败）→ 写默认配置，**不**让 app 崩。
- 写失败（磁盘满/权限）→ `try? data.write(to:options:[.atomic])` 吞掉，内存 config 仍更新（热生效），下次启动会重新尝试写盘。
- 不抛错到上游：`load()`/`save()`/`snapshot()` 都是非 throwing（`actor` 方法直接返回）。

### CmdRunner：try? + log

`CmdRunner.run`（`Actions/ActionDispatcher.swift`）用 `try?` + `NSLog` 吞错，永不抛到上游：
```swift
do {
    try p.run()             // Process.run() 异步启动，等价 subprocess.Popen
} catch {
    NSLog("[OpenVibeBoard] cmd 执行失败: \(cmd) — \(error.localizedDescription)")
}
```

- 命令不存在 / 权限不足 / sandbox 拒绝 → log + 返回，不影响下一次按键。
- stdout/stderr 丢弃（`/dev/null`，对齐 v0.1 的 `subprocess.DEVNULL`）。

> **sandbox 限制**：sandboxed app 的 `Process.run("/bin/sh -c ...")` 默认只能执行 `/bin` / `/usr/bin` 下的系统二进制。`defaultConfig` 的 k1=`open -a Codex`（`/usr/bin/open`）✅ 不受影响。用户自定义脚本路径可能被拒（主会话裁决：不预防性加 entitlement）。

### ActionDispatcher：权限守门 + ignore 分支

`ActionDispatcher.handle` 的错误路径（`Actions/ActionDispatcher.swift`）：
1. **配置查不到**：`guard let cfg = await config.snapshot()[event.button] else { return }` —— 静默跳过（对齐 v0.1 `CONFIG.get(button)` 返回 None）。
2. **Accessibility 未授权**：`guard Accessibility.isTrusted else { lastDeniedAt = Date(); log("⚠️ 未授权辅助功能..."); return }` —— log + 菜单栏图标提示，不发任何 CGEvent。
3. **parseKey 无法识别**：`decideAction` 返回 `.ignore` → `fireDown` 的 `.ignore` 分支 log「⚠️ 无法解析 key 或未知 type」。

---

## CGEvent nil 守门（替代 v0.1 的 optional import 降级）

v0.1 用 `try/except ImportError` 包 pyobjc，降级到 `HAS_CGEVENT` flag（import 失败 → hold 模式静默无效）。Swift 不需要这套——CoreGraphics 是系统框架，link 即有。

Swift 的对应降级是 **CGEvent 构造返回 nil 时 guard let 吞掉**（`Key/KeyInjector.swift`）：
```swift
private static let eventSource: CGEventSource? = CGEventSource(stateID: .hidSystemState)

static func tap(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
    guard let src = eventSource else { return }                    // eventSource nil → 静默返回
    if let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true) {
        down.flags = modifiers
        down.post(tap: .cghidEventTap)                             // CGEvent nil → 不 post
    }
    // keyup 同理
}
```

- `CGEventSource(stateID:)` 是 failable init（极少数情况返回 nil）。
- `CGEvent(keyboardEventSource:virtualKey:keyDown:)` 也是 failable。
- 两者 nil 时 `guard let` 吞掉，方法静默返回——对齐 v0.1 的 `HAS_CGEVENT` 降级语义（系统资源不足时 hold 模式静默无效，不让 app 崩）。

> 真正会让 CGEvent 完全失效的是 **Accessibility 未授权**（见上面 ActionDispatcher 权限守门），不是 import 失败。授权缺失由 `ActionDispatcher.handle` 守门检查，不在 `KeyInjector` 内部检查（避免每次按键都查系统调用）。

---

## 串口解析容错

`SerialMonitor.parseLine`（`Serial/SerialMonitor.swift`）用正则匹配，没匹配就返回 nil：
```swift
nonisolated static func parseLine(_ line: String) -> ButtonEvent? {
    let match = linePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    guard let match = match, match.numberOfRanges >= 3 else { return nil }
    // 提 capture group...
}
```

- 坏行（非 `button down/up kN` 格式）→ nil → delegate 里 `guard let event = parseLine(line) else { return }` 跳过。
- `ORSSerialPacketDescriptor` 保证只有匹配 `button (down|up) (k\d+)` 的整包才交付给 delegate，所以坏字节流不会进来（ORSSerialPort 内部缓冲 + 正则匹配）。
- 不对每条坏日志报警（会刷屏），对齐 v0.1 的「`decode("utf-8", "ignore")` 丢弃坏字节，正则没匹配就跳过」。

`String(data:encoding:.utf8)` 解码失败（非 UTF8 字节）→ nil → 跳过，对齐 v0.1 的 `decode("utf-8", "ignore")`。

---

## 权限缺失 = 警告，非崩溃

- **Accessibility 未授权** —— `ActionDispatcher.handle` 守门 log + `lastDeniedAt = Date()`（菜单栏图标变红提示）+ 不发 CGEvent。`Accessibility.ensure()` 在启动时弹一次系统对话框，运行时不重复弹（避免骚扰）。
- **串口 entitlement 缺** —— `serialPort(_:didEncounterError:)` 收到 EPERM(1) → log + status=.error + 重连（重连修不了，但让用户改 entitlement 后无需重启）。
- **SMAppService register/unregister 失败** —— `LaunchAtLogin.enable/disable` 用 `do/try/catch` 吞错 + log（「大声失败」规则 12：不静默吞，log 错误让 UI 勾选态反映未注册）。

权限授权是运行前置条件，在 `OpenVibeBoardApp.init`（启动时弹授权对话框）+ `MenuBarView`（未授权红色提示）+ 日志里声明。改动涉及权限时同步更新这些位置。

---

## 不定义自定义异常类

这个规模不需要。Swift 的错误处理层级：
- **可恢复错误**（IO / Process / SMAppService）→ `try?` 吞掉 + log，或 `do/try/catch` + log。
- **编程错误**（nil 解包 / 数组越界 / actor 隔离违规）→ Swift 运行时 crash（fatalError），不该 try/catch。
- **不可恢复系统错误**（CGEvent nil / CGEventSource nil）→ `guard let` 吞掉静默降级。

不要定义 `OpenVibeBoardError` 之类的自定义 enum——所有错误点要么用 `try?`（不需要区分原因），要么用 `NSPOSIXErrorDomain` 的系统错误码（串口）+ `error.localizedDescription`（Process/SMAppService）。

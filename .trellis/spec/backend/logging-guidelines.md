# 日志约定

> 每个模块自带 `log()` 私有包装，走 stderr（不缓冲），格式 `[HH:MM:SS] msg`。menu bar app 的 stdout 可能被 buffer，所以走 stderr + 自己拼时间戳。

---

## log() 包装（每个模块一份）

`ActionDispatcher` / `SerialMonitor` / `LaunchAtLogin` / `KeyMappingsView` 各有一个 `private static func log(_:)`（或 `private func log`），实现统一：

```swift
private static func log(_ msg: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(msg)\n"
    FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
}
```

- 格式固定：`[HH:MM:SS] <msg>`（`DateFormatter` 的 `.mediumStyle` 时间样式，对齐 v0.1 的 `time.strftime('%H:%M:%S')`）。
- **走 stderr**（`FileHandle.standardError`），不走 stdout —— menu bar app（LSUIElement accessory）的 stdout 可能被系统 buffer，stderr 立即可见（对齐 v0.1 `print(..., flush=True)` 的「必须 flush」语义）。
- `?? Data()` 兜底：极端情况 msg 含无法编码 UTF8 的字符时不崩。
- 末尾 `\n` 必须有（stderr 不自动换行）。

**不要**引入 `os_log` / `Logger` / `NSLog`（除 `CmdRunner.run` 的失败路径用 `NSLog`，因那是 Process 错误，走系统日志更合适）。menu bar app 在终端前台跑（开发时 `open ...app` 或 `xcodebuild` run），日志直接给人看，统一 stderr 包装即可。`NSLog` 会带额外系统前缀 + 走系统日志库，与这里的「直接给人看」语义不一致。

> **例外**：`CmdRunner.run` 的 catch 路径用 `NSLog("[OpenVibeBoard] cmd 执行失败: ...")`。原因：CmdRunner 是 `enum` + `static func`（无实例），且命令执行失败是低频系统级错误，走系统日志让 Console.app 也能看到。其余模块统一用 stderr 包装。

---

## 何时记

| 事件 | 示例 | 位置 |
|------|------|------|
| 串口打开 | `串口已打开` | `SerialMonitor.serialPortWasOpened` |
| 串口错误 | `⚠️ 串口错误: NSPOSIXErrorDomain 16 ...` / `⚠️ 串口被移除（设备拔了？），5 秒后重连` | `SerialMonitor.serialPort(_:didEncounterError:)` / `serialPortWasRemovedFromSystem` |
| 按键事件 | `k3 ▼ down` / `k3 ▲ up` | `SerialMonitor.serialPort(_:didReceivePacket:matchingDescriptor:)` |
| 动作触发 | `k1 -> 打开 Codex` / `k2 -> 输入文本 继续` / `k4 ▼ 按住 option+d` / `k4 ▲ 释放` | `ActionDispatcher.fireDown/fireUp` |
| parseKey 失败 | `⚠️ 无法解析 key 或未知 type: key zzz` | `ActionDispatcher.fireDown` 的 `.ignore` 分支 |
| Accessibility 未授权 | `⚠️ 未授权辅助功能，k4 ▼ 已忽略` | `ActionDispatcher.handle` |
| 配置更新 | `配置已保存并热生效` | `KeyMappingsView.save` |
| 开机自启 | `已注册开机自启（status: 已启用）` / `已取消开机自启` / `⚠️ 注册开机自启失败：...` | `LaunchAtLogin.enable/disable` |
| cmd 执行失败 | `[OpenVibeBoard] cmd 执行失败: open -a X — ...` | `CmdRunner.run`（NSLog） |

用 emoji/箭头（`▼` `▲` `⚠`）做视觉区分，便于在终端滚动里快速定位 down/up/告警。对齐 v0.1 的视觉约定。

---

## 不记什么

- **不记** `config.json` 的完整内容 —— value 字段可能含 shell 命令或敏感路径，只记 `desc`（对齐 v0.1）。
- **不记** 串口原始字节流 —— ORSSerialPacketDescriptor 已过滤，只记解析后的按键事件（`k3 ▼ down`）。
- **不记** 每次 Settings 打开/关闭 —— SwiftUI 场景生命周期不打日志。
- **不记** Accessibility 每次检查（纳秒级，每次按键都查）—— 只在未授权触发守门时记一次。

---

## 与 v0.1 的差异

v0.1 用 `print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)`（stdout + flush）。Swift 改 stderr 包装，原因：
- menu bar app（LSUIElement）无终端 attached，stdout 默认行缓冲或全缓冲，`print` 的输出可能看不到。
- stderr 是无缓冲的（POSIX 惯例），写进去立即可见。
- `DateFormatter.localizedString` 比 `time.strftime` 多本地化（系统语言的时间格式），但不影响可读性。

格式（`[HH:MM:SS] msg`）、何时记、不记什么、视觉区分（emoji/箭头）全部对齐 v0.1，无语义变化。

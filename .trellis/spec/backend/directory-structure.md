# 目录与架构

> Swift 原生 macOS app，按职责分模块。**不**回到 v0.1 的单文件 `vibe_control.py`——Swift 习惯按类型分文件，且 SwiftUI 场景/视图/模型/注入器有天然边界。

---

## 三大职责

OpenVibeBoard 是 menu bar app，一个进程做三件事：

1. **状态栏 UI** —— `MenuBarExtra`（`OpenVibeBoardApp.swift`）+ `MenuBarView`：状态栏图标、串口连接状态、Accessibility 授权提示、开机自启开关、打开设置、退出。
2. **串口监听** —— `SerialMonitor`（`@MainActor` ObservableObject）：开 `/dev/cu.usbmodem3101`，ORSSerialPort 按包交付匹配 `button (down|up) (k\d+)` 的行，解析成 `ButtonEvent` 经 `PassthroughSubject` 推下游。
3. **动作分发** —— `ActionDispatcher`（`@MainActor` ObservableObject）：订阅 `SerialMonitor.buttonEvents`，按 config 的 `type`/`mode` 分发到 `CmdRunner` / `TextInjector` / `KeyInjector`。

`@main` 启动顺序（`OpenVibeBoardApp.init`）：
1. 构造 `SerialMonitor`（`@StateObject`，init 后下一个 main runloop 自动 `start()` 开串口）。
2. 构造 `ActionDispatcher(serial:)`（订阅 buttonEvents）。
3. `Task.detached` → `ConfigStore.shared.load()`（首启写默认配置到 Application Support，已存在则加载）。
4. `Task.detached` → `Accessibility.ensure()`（首次弹系统授权对话框）。

---

## 目录树

```
OpenVibeBoard.xcodeproj                xcodegen generate 生成（不要手写 .pbxproj）
project.yml                            xcodegen 声明式配置（ORSSerialPort SPM / deployment 15 / 两 target）
OpenVibeBoard/
  OpenVibeBoardApp.swift               @main：MenuBarExtra + Settings 两 scene，构造 SerialMonitor/ActionDispatcher
  MenuBarView.swift                    状态栏菜单（状态/开关/退出）
  Models/
    Config.swift                       KeyConfig / Config Codable + defaultConfig + ConfigStore actor
  Serial/
    SerialMonitor.swift                ORSSerialPort 封装 + parseLine 纯函数 + 重连
  Actions/
    ActionDispatcher.swift             动作分发 + decideAction 纯函数 + Action 枚举 + CmdRunner + TextInjector
  Key/
    KeyInjector.swift                  CGEvent 按键注入：parseKey / descriptor / tap / press / release
  Settings/
    SettingsView.swift                 Settings 场景根
    KeyMappingsView.swift              sidebar-detail 映射列表 + 固定保存栏
    KeyMappingEditorView.swift         单个映射的类型化编辑表单
    KeyRecorderView.swift              AppKit 键盘事件采集 + SwiftUI keycap 展示
  LaunchAtLogin/
    LaunchAtLogin.swift                SMAppService.mainApp register/unregister/状态查询
  Permissions/
    Accessibility.swift                AXIsProcessTrusted 检查/请求
  Info.plist                           LSUIElement=true（menu bar accessory 模式）
  OpenVibeBoard.entitlements           app-sandbox + com.apple.security.device.serial
OpenVibeBoardTests/                    Swift Testing（bundle.unit-test），测纯逻辑
archive/python-v0.1/                   v0.1 Python 实现（归档，作逻辑参考）
```

---

## 分发链（核心数据流）

```
ESP32 串口字节流
  └─ ORSSerialPort 缓冲 + 正则匹配 "button (down|up) (k\d+)" 按包交付
       └─ SerialMonitor.parseLine(line) → ButtonEvent(button, pressed)
            └─ PassthroughSubject.send(event)
                 └─ ActionDispatcher.handle(event)        // @MainActor
                      ├─ await ConfigStore.shared.snapshot()[button]   // 读配置快照
                      ├─ guard Accessibility.isTrusted else { log + return }   // 权限守门
                      └─ decideAction(cfg, pressed) → Action           // 纯函数决策
                           └─ switch Action → DispatchQueue.global 执行副作用：
                                ├─ .runCmd(value)           → CmdRunner.run          // Process（非阻塞）
                                ├─ .injectText(value, enter)→ TextInjector.inject    // NSPasteboard + Cmd+V + 可选 Enter
                                ├─ .tapKey(vk, mods)        → KeyInjector.tap        // CGEvent keydown 立即 keyup
                                ├─ .pressKey(vk, mods)      → KeyInjector.press      // CGEvent keydown 挂 flag（hold 按下）
                                ├─ .releaseKey(vk)          → KeyInjector.release    // CGEvent keyup 不带 flag（hold 松开）
                                └─ .ignore                   → log（parseKey nil / 未知 type / up 非 hold）
```

**关键约束**：
- 新增动作类型时，在 `Action` 枚举 + `decideAction` 的 switch + `fireDown`/`fireUp` 的执行 switch 三处加，**不要**绕过分发链直接在 `SerialMonitor` 或 delegate 里调 `Process` / `KeyInjector`。
- `decideAction` 是 `nonisolated static` 纯函数（只读入参 + 调 `KeyInjector.parseKey`），不触任何 main actor 状态——这是阶段 F 重构的可测性核心。副作用（dispatch / log / Process / CGEvent）全在 `fireDown`/`fireUp`。

---

## config.json schema

```json
{
  "k1": {"type": "cmd",  "value": "open -a Codex", "mode": "tap",  "desc": "打开 Codex"},
  "k2": {"type": "text", "value": "继续",           "enter": true, "desc": "输入'继续'并回车"},
  "k3": {"type": "key",  "value": "ctrl+c",         "mode": "tap",  "desc": "Ctrl+C"},
  "k4": {"type": "key",  "value": "option+d",       "mode": "hold", "desc": "语音(按住)"}
}
```

- **键名**：`k1`/`k2`/...，对应固件日志里的 `kN`。`SerialMonitor.parseLine` 的正则用 `\d+`（容纳 k10+）。
- **`type`**：`"cmd"`（shell 命令）/ `"key"`（击键）/ `"text"`（输入文本）。cmd/text 的 mode 无效。
- **`value`**：
  - cmd：shell 字符串（如 `"open -a Codex"`）。
  - key：含可选 modifier 的描述（`option+d` / `cmd+shift+d` / `esc` / `enter` / 单字符）。Settings 录制器会生成规范描述。
  - text：要输入的文本（中文等任意字符）。
- **`mode`**：`"tap"`（瞬时，CGEvent 单发 keydown+keyup）或 `"hold"`（按住，CGEvent keydown 等松开 keyup）。**仅 key 类型有效**。
- **`enter`**：仅 text 类型，布尔（默认 true），控制粘贴后是否补一个回车。
- **`desc`**：纯展示用，菜单栏日志和 Settings Section header 出现。

**Swift 模型**（`Models/Config.swift`）：
```swift
struct KeyConfig: Codable, Equatable {
    var type: String       // "cmd" | "key" | "text"
    var value: String
    var mode: String?      // 仅 key：tap | hold
    var enter: Bool?       // 仅 text：粘贴后是否回车（默认 true）
    var desc: String?      // 展示用
}
typealias Config = [String: KeyConfig]
```

字段全 `Optional`（除 type/value）——Codable 解码 v0.1 写的 config.json（缺 mode/enter/desc 字段）不报错，缺省走默认语义。

**持久化**（`ConfigStore` actor）：
- 路径：`~/Library/Application Support/OpenVibeBoard/config.json`（`FileManager.url(for:.applicationSupportDirectory)`）。
- 首次运行：文件不存在 → 写 `defaultConfig`（k1-k4，移植 v0.1）。
- `load()` 幂等（多次调只读一次盘）；`snapshot()` 返回拷贝；`save(_:)` 原子写盘 + 内存更新。
- 写盘用 `.prettyPrinted + .sortedKeys`（对齐 v0.1 的 `indent=2`，sortedKeys 让 git diff 稳定）+ `.atomic`（对齐 v0.1 的临时文件 + rename）。
- `save()` 后**热生效**：下一次物理按键 `ActionDispatcher.handle` 调 `snapshot()` 读到新配置，无需重启 app。

**并发语义**（对齐 v0.1 的 `CONFIG_LOCK`）：
- `ConfigStore` 是 `actor`，所有读写经 actor 串行化。
- 串口线程（`ActionDispatcher.handle` 在 `@MainActor`，但读 config 走 `await config.snapshot()` 跨 actor）与 Settings UI（`@MainActor` 的 `KeyMappingsView.save` 走 `await ConfigStore.shared.save`）共用 `.shared` 单例，无数据竞争。

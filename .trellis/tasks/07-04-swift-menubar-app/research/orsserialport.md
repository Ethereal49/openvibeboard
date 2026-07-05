# Research: ORSSerialPort（阶段 B 串口监听）

- **Query**: 为 v0.2.0 Swift menu bar app 阶段 B 引入 ORSSerialPort，监听 `/dev/cu.usbmodem3101`，按行解析 `button down kN` / `button up kN`，复刻 Python `vibe_control.py` 的 `serial_loop()`
- **Scope**: external（库文档 + 源码 + issue tracker）
- **Date**: 2026-07-05
- **Tool note**: 任务原指定用 context7 查 ORSSerialPort；本环境未挂载 context7 MCP，全部结论改由 GitHub 官方仓库源码 / README / wiki / issue 直接取证（URL 见末尾），比 context7 更权威。

---

## TL;DR（先看这 7 条）

1. **唯一可用源**：`armadsen/ORSSerialPort`（GitHub 唯一官方仓库，769 stars，未 archived）。其他拼写（Armherder / openreelsoftware.com 域名）都已失效。
2. **最新稳定 tag = `2.1.0`**（2019-06-13），但仓库持续维护到 2023-11-03（SPM 修复、目录重组）。**SPM 直接锁 `from: "2.1.0"` 即可**，没有更新版本。
3. **package product 名是 `ORSSerial`**（不是 `ORSSerialPort`），Swift 里 `import ORSSerial`。这是最容易踩的拼写坑。
4. **Sandbox 结论（关键）**：menu bar app **可以保留 sandbox**，**必须**在 `.entitlements` 加一行 `com.apple.security.device.serial = true`。这是作者本人在 issue #10/#156/#171 里的明确答复，wiki 「Use in Sandboxed Applications」章节同款结论。**不需要**禁用 sandbox、不需要 USB entitlement、不需要临时例外。
5. **回调线程（关键）**：`ORSSerialPortDelegate` 全部方法**强制在 main queue 调用**（源码 `ORSSerialPort.m:530/557/572/597/790` 处处 `dispatch_async(dispatch_get_main_queue(), ...)`，头文件 `ORSSerialPort.h:567` 明确写 "All ORSSerialPortDelegate methods are always called on the main queue"）。所以更新 SwiftUI `@Published` 状态**不需要**再切 `@MainActor` / `DispatchQueue.main`——直接赋值即可。
6. **不要自己手写按字节缓冲切行**。ORSSerialPort 自带 packet parser：用 `ORSSerialPacketDescriptor(regularExpression:maximumPacketLength:userInfo:)` 喂一个匹配 `button (down|up) k\d+` 的 `NSRegularExpression`，注册到 port，delegate 走 `serialPort(_:didReceivePacket:matchingDescriptor:)`，库帮你缓冲、按包交付。比 Python 版手写 `buf += chunk; buf.split(b"\n", 1)` 干净。
7. **`open()` 是 void，失败走 delegate**。`-open` 不返回 Bool，开打不开时通过 `serialPort(_:didEncounterError:)` 异步报 `NSPOSIXErrorDomain Code=1 "Operation not permitted"`（sandbox 缺 entitlement）或 `EBUSY/ENOENT`（端口不存在 / 被占）。Swift 里要靠 delegate 收错误，不能 try/catch。

---

## SPM 依赖（可直接抄进 `project.yml`）

### XcodeGen 语法（在现有 `project.yml` 上扩展）

现有 `project.yml`（commit `a316f3a`）目前**没有任何 packages**、target 也没有 `dependencies`。阶段 B 在顶层加 `packages:`，target 里加 `dependencies:`：

```yaml
name: VibeBoard
options:
  bundleIdPrefix: com.ethereal49
  deploymentTarget:
    macOS: "13.0"
  developmentLanguage: zh-Hans
packages:                                    # ★ 新增：声明 SPM 远程依赖
  ORSSerialPort:
    url: https://github.com/armadsen/ORSSerialPort.git
    from: "2.1.0"                            # 最新稳定 tag = 2.1.0（2019-06-13）；不要写更高版本，不存在
settings:
  base:
    MARKETING_VERSION: "0.2.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "5.0"
    # ⚠ 阶段 B 注意：现有 project.yml 关掉了 code signing（CODE_SIGNING_REQUIRED: NO 等）。
    #     跑串口 entitlement 测试时，sandbox+entitlement 路径需要打开签名（至少 ad-hoc）；
    #     开发期可继续关，但要在 README/设计文档里记录「发布构建需开签名」。
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGNING_REQUIRED: NO
    CODE_SIGNING_ALLOWED: NO
targets:
  VibeBoard:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: VibeBoard
    dependencies:                            # ★ 新增：target 依赖
      - package: ORSSerialPort
        product: ORSSerial                   # ★ product 名是 ORSSerial，不是 ORSSerialPort（极易写错）
    info: { ... 不变 ... }
    settings: { ... 不变 ... }
```

跑 `xcodegen generate` 后，Xcode 会把 ORSSerialPort 解析到 `VibeBoard.xcodeproj` 的 Package Dependencies。

### 验证过的来源（ORSSerialPort wiki: Installing ORSSerialPort → "Using Swift Package Manager"）

```
.package(url: "https://github.com/armadsen/ORSSerialPort.git", from: "2.1.0"),
// target 里：
.product(name: "ORSSerial", package: "ORSSerialPort")
```

`Package.swift`（仓库根）：`swift-tools-version:5.0`，platform `.macOS(.v10_10)`，product 名 `ORSSerial`，target `ORSSerial`，path `Sources`。

---

## 核心代码骨架

### 模型：复刻 Python `serial_loop()` 的语义

Python `vibe_control.py:209-230` 做的事：开 115200、读 chunk、`buf += chunk`、按 `\n` 切、`DOWN_RE/UP_RE` 正则匹配 `button (down|up) (k\d)`、`fire_down/fire_up(button)`、`SerialException` 整段吞掉打日志（守护进程不崩）。

Swift 等价实现用 ORSSerialPacketDescriptor 把"按行+正则"两件事一次做完：

```swift
import ORSSerial
import Combine
import Foundation

@MainActor                    // 因为 delegate 全部在 main queue 回调，且要直接更新 SwiftUI 状态
final class SerialMonitor: NSObject, ORSSerialPortDelegate {

    static let path = "/dev/cu.usbmodem3101"      // 对齐 Python 的 PORT_SERIAL
    private static let linePattern = try! NSRegularExpression(
        pattern: "button (down|up) (k\\d+)"        // 同时吃 down/up，capture group 区分
    )

    private var port: ORSSerialPort?
    private let lineDescriptor: ORSSerialPacketDescriptor

    /// 给 SwiftUI/MenuBarView 订阅的最新事件（替代 Python 的 fire_down/fire_up 间接调用）
    let buttonEvents = PassthroughSubject<ButtonEvent, Never>()

    struct ButtonEvent { let button: String; let pressed: Bool }

    override init() {
        // maximumPacketLength 必须填，且要够大覆盖最长一行（"button down k12\n" ≈ 18 字节）
        lineDescriptor = ORSSerialPacketDescriptor(
            regularExpression: SerialMonitor.linePattern,
            maximumPacketLength: 64,
            userInfo: nil
        )
        super.init()
    }

    func start() {
        guard port == nil else { return }
        guard let p = ORSSerialPort(path: Self.path) else {   // path 不存在返回 nil
            // 复刻 Python 首次启动失败的语义：打日志、不崩、稍后重试
            NSLog("[VibeBoard] 串口 \(Self.path) 不可用，等重连")
            return
        }
        p.delegate = self
        p.baudRate = 115200               // ★ 默认是 B19200（见 ORSSerialPort.m:183），必须显式设
        p.allowsNonStandardBaudRates = true   // 115200 是标准 baud，但保险起见开着
        p.numberOfStopBits = 1
        p.parity = .none                  // ORSSerialPortParityNone
        p.startListeningForPackets(matching: lineDescriptor)
        p.open()                          // void；失败走 didEncounterError
        port = p
    }

    func stop() {
        port?.close()
        port = nil
    }

    // MARK: - ORSSerialPortDelegate（全部 main queue 回调）

    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        NSLog("[VibeBoard] 串口已打开")
    }

    // 按行解析走这里（descriptor 帮你缓冲+切包）。原始字节流走 didReceiveData，本场景不需要。
    func serialPort(_ serialPort: ORSSerialPort,
                    didReceivePacket packetData: Data,
                    matchingDescriptor descriptor: ORSSerialPacketDescriptor) {
        guard let line = String(data: packetData, encoding: .utf8) else { return }
        // line 形如 "button down k3"；descriptor 已保证匹配正则
        let full = NSRegularExpression.fullMatch(in: line, pattern: "button (down|up) (k\\d+)")
        let pressed = full[1] == "down"
        let button = full[2]                // "k3"
        buttonEvents.send(ButtonEvent(button: button, pressed: pressed))
        // 下游（MenuBarView/ActionDispatcher）订阅 buttonEvents，等价于 Python 的 fire_down/fire_up
    }

    // 必填（@required）：USB-CDC 设备拔掉 / 断电时回调
    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        NSLog("[VibeBoard] 串口被移除（设备拔了？），5 秒后重连")
        port = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.start()                   // 实现断线重连，对应 Python 的 while True 重试语义
        }
    }

    // 开打不开 / read 出错 / ioctl 出错都走这里（NSPOSIXErrorDomain）
    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        let nsError = error as NSError
        NSLog("[VibeBoard] 串口错误: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
        // Code=1 EPERM "Operation not permitted" → 检查 entitlement（见下节）
        // Code=6 ENXIO → 设备已拔，serialPortWasRemovedFromSystem 也会来
        // Code=16 EBUSY → 端口被占（其他进程开着），等会儿重试
        if nsError.code == Int(EBUSY) || nsError.code == Int(ENOENT) {
            port?.close(); port = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.start() }
        }
    }

    func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        NSLog("[VibeBoard] 串口已关闭")
    }
}

// 小工具：把 NSRegularExpression 的 firstMatch + capture group 提出来
private extension NSRegularExpression {
    static func fullMatch(in s: String, pattern: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern)
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return [] }
        return (0..<m.numberOfRanges).compactMap { i in
            let r = Range(m.range(at: i), in: s); return r.map { String(s[$0]) }
        }
    }
}
```

### 三个跟 Python 行为差异要点

| Python | Swift/ORSSerialPort | 怎么处理 |
|---|---|---|
| `with serial.Serial(...) as s` —— 上下文管理器自动 close | `ORSSerialPort` 没 `defer { close() }`；NSObject 实例由 ARC 释放 | 显式 `stop()`（app 退出时调），重连前手动 `close()` |
| `serial.SerialException` —— 整段 try/except 包住 while 循环 | 错误分散到 delegate：`didEncounterError` / `serialPortWasRemovedFromSystem` | 在每个 delegate 方法里独立降级（打日志 + 重连），app 永不崩 |
| `buf += chunk; buf.split(b"\n",1)` 手写缓冲 | `ORSSerialPacketDescriptor` + `startListeningForPackets` 内置缓冲 | 直接用 descriptor，**不要**再实现 `didReceiveData` 自己切（会双重缓冲） |

---

## Sandbox 与权限结论（明确版）

### 一句话

**保留 sandbox，加 `com.apple.security.device.serial = true`。不要关 sandbox。**

### 证据

- **作者本人答复（issue #10, 2013）**："ORSSerialPort can indeed be used in sandboxed apps. You need to set the `com.apple.security.device.serial` entitlement in your entitlements file (it's not a checkbox in Xcode, you have to add it manually)."——提问者照做后确认问题解决。
- **issue #156（2020）**：同样症状 `NSPOSIXErrorDomain Code=1 "Operation not permitted"`，作者答："you need to make sure you've included the `com.apple.security.device.serial` to your sandbox entitlements file." 提问者照做后确认完美解决。
- **issue #171（2021）**：作者答："If your app is sandboxed (the default Xcode Mac app template starts with sandboxing turned on), you'll need that or all attempts to open a serial port will fail."（提问者最后选了"删 sandbox"的偷懒方案，但作者推荐的是加 entitlement。）
- **官方 wiki 「Use in Sandboxed Applications」**："if you are using it in a sandboxed application, as required for apps submitted to the Mac App Store, you must add the `com.apple.security.device.serial` to your application project's sandbox entitlements file."

### 不需要加的（别加多余的）

- `com.apple.security.device.usb` —— USB 通用访问。**对 CDC-ACM 串口设备不需要**（issue #10 提问者原本加了这个也没用，正确的是 `device.serial`）。只有当你想用 IOKit 直接枚举 USB 时才需要；ORSSerialPort 走 `/dev/cu.*` 文件描述符路径，不需要 USB 栈。
- `com.apple.security.temporary-exception.*` —— 临时例外。完全不需要。
- `com.apple.security.network.*`、文件 User-Selected 等 —— 跟串口无关。

### 实操：给 `VibeBoard.entitlements` 加这一行

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.serial</key>     <!-- ★ 关键，就这一行 -->
    <true/>
</dict>
</plist>
```

XcodeGen 在 `project.yml` 里挂 entitlements：

```yaml
targets:
  VibeBoard:
    ...
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ethereal49.VibeBoard
        CODE_SIGN_ENTITLEMENTS: VibeBoard/VibeBoard.entitlements   # ★ 新增
        # ⚠ 同步打开签名（否则 entitlement 不生效）：
        CODE_SIGN_IDENTITY: "-"            # ad-hoc 开发签名就够，本机跑通
        CODE_SIGNING_REQUIRED: YES
        CODE_SIGNING_ALLOWED: YES
```

**注意现有 `project.yml` 把 `CODE_SIGNING_REQUIRED/ALLOWED` 都设了 NO**（阶段 A 为了简化）。阶段 B 引入 entitlement 后，这两个必须翻成 YES，否则 Xcode 不会嵌入 entitlements，sandbox 拒绝打开 `/dev/cu.*`。开发签名 `-`（ad-hoc）就够本机调试；上 App Store 再换 Developer ID。

### ESP32-S3 CDC 兼容性

ESP32-S3 板子枚举成 USB CDC-ACM，macOS 自动绑 `/dev/cu.usbmodem*`，**对 ORSSerialPort 透明**——它只是 `open("/dev/cu.usbmodem3101", O_RDWR|...)` + termios，跟任何 CDC-ACM 设备一样。无特殊驱动、无特殊配置。PRD 风险栏提到的"需验证 ESP32-S3 CDC 兼容"在 sandboxed+entitlement 配置下不构成额外风险。

---

## 已知坑（按优先级）

### 1. 默认 baudRate 是 19200，不是 115200（**踩过最频繁的坑**）

`ORSSerialPort.m:183` `self.baudRate = @B19200;` 是 init 默认值。Python 版（`vibe_control.py:64` `BAUD = 115200`）跑的是 115200。**必须**在 `open()` 之前显式 `port.baudRate = 115200`，否则收到的全是乱码（baud 不匹配，字节错位），descriptor 也匹配不到 `button down k\d`。设了 baudRate 会触发 `setPortOptions` 重新 `tcsetattr`，运行中改 baudRate 也会即时生效。

### 2. `open()` 后才设 baudRate 等于丢首批数据

`setBaudRate:` 内部调 `setPortOptions` 调 `tcsetattr`。如果 `open()` 先调，端口已经在按 19200 读，可能错过开机首包。**正确顺序：先设 baudRate → 再 open()**（上面骨架代码就是这个顺序）。

### 3. Swift 6 concurrency 警告（不是错误）

`Package.swift` 是 `swift-tools-version:5.0`，**没有任何 `Sendable` 标注**，仓库至今没合过 Swift 6 适配 PR（issue tracker 搜 "Sendable" 零结果）。在 `SWIFT_VERSION: 5.0` 模式（现有 project.yml 已采用）下没警告。若未来切 Swift 6 strict concurrency，`ORSSerialPort` 实例跨 `@MainActor` 边界可能报 `Sendable` 警告——届时用 `@preconcurrency import ORSSerial` 或 `nonisolated(unsafe)` 标注 `port` 属性临时压制，等上游或自行 fork 修。**阶段 B 不用管。**

### 4. delegate 回调在 main queue（不是坑，是 feature）

不要在 delegate 方法里做重活（解析 JSON、subprocess、CGEvent 注入），否则阻塞主线程导致 UI 卡顿。menu bar app 主线程还要画菜单，**重活 dispatch 到 global queue**：

```swift
func serialPort(_ port: ORSSerialPort, didReceivePacket data: Data, matchingDescriptor d: ORSSerialPacketDescriptor) {
    let event = parse(data)
    DispatchQueue.global().async { ActionDispatcher.shared.dispatch(event) }   // CGEvent/subprocess 在后台
    // 只把状态字段回主线程更新 UI
}
```

### 5. 设备拔了不主动通知 port 失效，但 port 实例不能用

`serialPortWasRemovedFromSystem(_:)` 是 **`@required`** delegate 方法（不实现编译过、运行时崩），头文件 `ORSSerialPort.h:588` 明确："discard any strong references you have maintained for the passed in `serialPort` object. The behavior of `ORSSerialPort` instances whose underlying serial port has been removed from the system is undefined." 收到回调后**立刻**置 `self.port = nil`，重连时 `ORSSerialPort(path:)` 新建实例。

### 6. 检测设备拔除靠后台 CTS/DSR 轮询（10ms 间隔）

`ORSSerialPort.m:316-330` 起了一个 `DISPATCH_SOURCE_TYPE_TIMER`，每 10ms `ioctl(fd, TIOCMGET)`，errno == ENXIO 时触发 `cleanupAfterSystemRemoval` → `serialPortWasRemovedFromSystem`。**这是 unplug 检测机制**，依赖 `TIOCMGET` ioctl 在 fd 失效时返回 ENXIO。CDC-ACM 驱动（macOS 自带 `AppleUSBACM`）实测支持。如果未来换纯虚拟串口（无 modem 线）可能不灵，对 ESP32-S3 CDC 没问题。

### 7. 包缓冲按 `maximumPacketLength` 截断

`ORSSerialPacketDescriptor` 的 `maximumPacketLength` 是**硬上限**——单包字节超过这个长度，descriptor 丢弃或截断（看实现）。`button down k12\n` 最长 18 字节，填 64 留足余量；填太小（比如 16）会丢 `k10`+ 的包。**别填 0 或 1**。

### 8. 去抖（debounce）

固件层如果对单次物理按键发了多次 down/up（机械抖动），ORSSerialPort 这层不管去抖，原样把每包送给 delegate。Python 版也没做去抖（`serial_loop` 直接调 `fire_down`）。如果实测发现单按触发多次，在 `SerialMonitor` 里加时间窗去抖：记录 `lastDownTime[button]`，相邻 < 30ms 的同 button down 忽略。**阶段 B 先不做，看实测是否需要。**

### 9. 多实例串扰（issue #197 open）

issue #197 反复 open/close 后 port 开不出来——这是已知 bug，未修。阶段 B 不要做"健康检查型"频繁 open/close（比如每秒探活）。**只在 start/stop/重连时 open/close**，正常监听期间一直保持 open，避免触发该 bug。

### 10. `requestResponseQueue` 是 ORSSerialPort 自管的后台队列

`ORSSerialPort.m:180` `self.requestHandlingQueue = dispatch_queue_create("com.openreelsoftware.ORSSerialPort.requestHandlingQueue", 0)`。这是 request/response API 内部用的，本场景（被动监听、不发请求）用不到，但要知道数据先到这条队列做 packet 解析，再 dispatch 到 main 调 delegate——所以从字节到达到 delegate 回调之间有一次队列跳转，延迟 < 1ms 可忽略。

---

## 来源引用

### 一手源码（已读）

- `armadsen/ORSSerialPort` master 分支（`gh api` 拉取，2026-07-05 状态）：
  - `README.md` —— SPM/CocoaPods/Carthage 用法、Swift 4 行示例
  - `Package.swift` —— `swift-tools-version:5.0`，`.macOS(.v10_10)`，product `ORSSerial`
  - `Sources/ORSSerial/ORSSerialPort.m` —— 默认 baudRate 19200（:183）、open() void（:255）、main queue dispatch（:530/557/572/597/790）、CTS/DSM 轮询 timer（:316-330）、tcsetattr 配置（:620-680）
  - `Sources/include/ORSSerial/ORSSerialPort.h` —— delegate protocol（:574-672），全 main queue 文档注释（:567），`startListeningForPacketsMatchingDescriptor:`（:320）
  - `Sources/include/ORSSerial/ORSSerialPacketDescriptor.h` —— 5 个 initializer（responseEvaluator / packetData / prefix+suffix / prefixString+suffixString / regularExpression）
  - `CHANGELOG.md` —— 2.1.0（2019-06-13）是最新 release，2.1.0 之后只有 SPM/目录整理 commit，无新 tag
- 仓库元数据：`default_branch: master`, `archived: false`, `pushed_at: 2023-11-03T14:19:49Z`, 769 stars
- Tags（前 15 个）：`2.1.0` > `2.1` > `2.0.2` > `2.0.1` > `2.0.0` > `1.8.x` ...
- Issues 全部用 `gh search issues --repo armadsen/ORSSerialPort "<kw>"` 取证：
  - sandbox: #10（closed, 作者答复加 device.serial）, #98（closed, sandboxed 下 IOKit 通知）, #156（closed, EPERM 加 device.serial）, #171（closed, open 返回 -1 加 device.serial 或关 sandbox）
  - Sendable / Swift 6 / concurrency: 零结果（搜过 open 和 closed）

### 二手 / wiki

- 官方 wiki 「Installing ORSSerialPort」之 "Using Swift Package Manager" 与 "Use in Sandboxed Applications" 章节（curl 拉取渲染 HTML）—— URL 与 SPM 写法、device.serial entitlement 结论出处
- 官方 wiki 「Getting Started」—— delegate protocol 总览（未全文取，头文件已含全部信息）

### 本仓库内部参考

- `/Users/ethereal/Documents/Code/openvibeboard/vibe_control.py:209-230` `serial_loop()` —— Python 串口解析逻辑（要复刻的语义源）
- `/Users/ethereal/Documents/Code/openvibeboard/vibe_control.py:81-82` `DOWN_RE` / `UP_RE` 正则定义
- `/Users/ethereal/Documents/Code/openvibeboard/vibe_control.py:64` `BAUD = 115200` 常量
- `/Users/ethereal/Documents/Code/openvibeboard/.trellis/tasks/07-04-swift-menubar-app/research/menubar-extra-and-scaffold.md` —— 阶段 A 研究（project.yml 模板、MenuBarExtra 骨架）
- `/Users/ethereal/Documents/Code/openvibeboard/.trellis/spec/backend/directory-structure.md` —— config.json schema、分发链
- `/Users/ethereal/Documents/Code/openvibeboard/project.yml` —— 当前 XcodeGen 配置（确认无 packages、CODE_SIGNING 关闭）

---

## Caveats / Not Found

- **未在真机验证**：所有结论基于源码静态分析 + issue tracker 证据。ESP32-S3 板子 + `/dev/cu.usbmodem3101` 路径 + sandboxed entitlement 配置的端到端实测，留到 implement 阶段跑 `xcodebuild` + 真机按键触发。
- **2.1.0 → master 之间的 commit 未发版**：仓库 2019 后的 SPM 修复、目录重组没有打 tag。锁 `from: "2.1.0"` SPM 解析的是 tag 2.1.0 的 commit（`2.1.0` tag 指向的 commit 是 `1d8197ca` "Fix building with Swift Package Manager due to angle bracket import"——这是 SPM 可构建的最旧稳定 commit，也是 wiki 推荐的 from 版本）。如果你需要更新的修复（比如 #197 反复 open/close 问题），只能锁到具体 commit SHA：`revision: "7e46ba1c"`，但这样会失去 `from:` 的语义版本兼容性。**默认建议 `from: "2.1.0"`**，遇到具体 bug 再 fork 或锁 revision。
- **Swift 6 严格并发**：未实测 Swift 6 模式下 ORSSerialPort 的 Sendable 警告。现有 project.yml 用 SWIFT_VERSION 5.0，本阶段不会触发；升级 Swift 6 时需重新评估。
- **未拉取 Getting Started / Packet Parsing API wiki 全文**：头文件注释已含全部 API 信息（参数、返回值、线程模型），wiki 主要是教程性质，跳过以节省调研时间。需要时可访问 https://github.com/armadsen/ORSSerialPort/wiki/Packet-Parsing-API。

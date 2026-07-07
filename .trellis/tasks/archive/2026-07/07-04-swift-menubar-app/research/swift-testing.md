# Swift Testing（F 阶段测试）

> 来源：context7 `/swiftlang/swift-testing`（2026-07-07）+ 项目可测性分析
> 环境：Xcode 26 / Swift 6.3.3 / macOS 26 —— Swift Testing 内置，无需额外依赖

## 核心 API

```swift
import Testing
import XCTest  // 仅在需要时（本项目尽量纯 Swift Testing）

@Test func twoPlusTwo() {
    #expect(2 + 2 == 4)
}

@Suite struct KeyConfigTests {
    @Test func defaults() async throws {
        let cfg = KeyConfig(type: "key", value: "esc", mode: "tap", enter: nil, desc: nil)
        #expect(cfg.type == "key")
    }
}

// 参数化（核心武器，覆盖分支用）
@Test("parseKey 单 modifier", arguments: [
    ("option+d", CGKeyCode(kVK_ANSI_D), CGEventFlags.maskAlternate),
    ("ctrl+c",   CGKeyCode(kVK_ANSI_C), CGEventFlags.maskControl),
    ("cmd+q",    CGKeyCode(kVK_ANSI_Q), CGEventFlags.maskCommand),
    ("shift+a",  CGKeyCode(kVK_ANSI_A), CGEventFlags.maskShift),
])
func parseKeyModifier(input: String, vk: CGKeyCode, flags: CGEventFlags) {
    let r = KeyInjector.parseKey(input)
    #expect(r != nil)
    #expect(r?.virtualKey == vk)
    #expect(r?.modifiers == flags)
}

// 失败用例
@Test func parseKeyInvalid() {
    #expect(KeyInjector.parseKey("xyz") == nil)
    #expect(KeyInjector.parseKey("ctrl+zzz") == nil)
}

// 需要 nil 之外的强解包用 #require
let parsed = try #require(KeyInjector.parseKey("esc"))
```

- `#expect(条件)` —— 断言，失败继续跑（收集所有失败）
- `#require(expr)` —— 失败抛错终止当前测试（用于强解包必须非空的场景）
- `@Test("名字")` —— 自定义显示名
- `arguments: [...]` —— 参数化，每个元素跑一次（默认并行）
- `@Suite` —— 分组（struct/actor）
- async/throws 原生支持（不用 XCTest 的 async await 套路）

## xcodegen 加测试 target

`project.yml` 加（与 OpenVibeBoard target 平级）：

```yaml
targets:
  OpenVibeBoard:
    # ...（不变）

  OpenVibeBoardTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: OpenVibeBoardTests
    dependencies:
      - target: OpenVibeBoard
```

- Swift Testing 在 `bundle.unit-test` target 默认可用（Xcode 16+），`import Testing` 直接用
- 测试文件放 `OpenVibeBoardTests/` 目录
- xcodegen 重生成后，scheme 自动含 test action

## 运行

```bash
xcodegen generate
xcodebuild test -project OpenVibeBoard.xcodeproj -scheme OpenVibeBoard -configuration Debug 2>&1 | tail -40
```

- Debug Dylib 坑不影响测试（测试 target 链接 app，Swift Testing 跑测试方法）
- 测试不需要 Accessibility/串口/SMAppService 授权（只测纯逻辑，不触副作用）

## 测试范围（用户已定：重构 ActionDispatcher 可测）

### 必测（纯逻辑，零重构）
1. **`KeyInjector.parseKey`**（核心 flags 坑的纯侧）—— 参数化覆盖：
   - 单 modifier：`option+d`/`ctrl+c`/`cmd+q`/`shift+a` → (vk, flags)
   - modifier 别名：`control+c`/`command+q`/`alt+d`/`opt+d`
   - 无 modifier 字母/数字：`a`/`d`/`1` → (vk, [])
   - 特殊键：`esc`/`escape`/`enter`/`return`/`space`/`tab`/`up`/`delete`
   - 非法：`xyz`/`ctrl+zzz`/`foo+bar` → nil
   - **多 modifier 不支持**：`ctrl+shift+d` → nil（`firstIndex(of: "+")` 拆第一个 `+` 后 charStr=`shift+d`，charKeyCode 查不到；与 Python `split("+",1)` 同源行为）
2. **`KeyConfig` / `Config` Codable** —— Python schema 兼容：
   - 编码 `KeyConfig(type:"key", value:"ctrl+c", mode:"tap", enter:nil, desc:"Ctrl+C")` → JSON → 解码回来相等
   - `Config`（字典）往返
   - 字段缺省：mode/enter/desc 为 nil 时编解码对称
3. **`defaultConfig`** —— 守护默认配置符合 Python 迁移意图：4 个键 k1-k4 存在 + 各自 type/value/mode 正确

### 小重构后测
4. **`ConfigStore`** —— 注入 URL（当前 configURL 是 fileprivate 全局硬编码）：
   - 重构：`ConfigStore` 加可注入的 URL 参数（`init(url: URL = configURL)`），shared 单例用默认值保持现状
   - 测：load 首启写默认 → 临时目录；save 原子写 → 读回；load 幂等（多次调只读一次盘）；snapshot 返回拷贝
5. **`SerialMonitor.parseLine`** —— 抽纯函数（当前正则提取埋在 `serialPort(_:didReceivePacket:matchingDescriptor:)` delegate 里）：
   - 重构：抽 `static func parseLine(_ line: String) -> ButtonEvent?`，delegate 调它
   - 测：`"button down k3"` → ButtonEvent(button:"k3", pressed:true)；`"button up k12"` → k12, false（验证 \d+ 容纳 k10+）；`"garbage"` → nil；`"button down k"` → nil

### 重构 ActionDispatcher 可测（核心）
6. 当前 `ActionDispatcher.handle/fireDown/fireUp` 把**纯分发逻辑**和**副作用**（KeyInjector/CmdRunner/TextInjector 静态 + DispatchQueue.global + Accessibility/ConfigStore 单例）耦合在一个方法，不可 mock。

   **重构方案**：抽纯函数 `decideAction`，返回 `Action` 枚举。fireDown/fireUp 改成「decide → execute」。

   ```swift
   extension ActionDispatcher {
       /// 分发动作（纯数据，Equatable 可断言）。
       enum Action: Equatable {
           case runCmd(String)
           case injectText(String, enter: Bool)
           case tapKey(virtualKey: CGKeyCode, modifiers: CGEventFlags)
           case pressKey(virtualKey: CGKeyCode, modifiers: CGEventFlags)
           case releaseKey(virtualKey: CGKeyCode)
           case ignore
       }

       /// 纯函数：决定做什么（含 parseKey）。Accessibility 守门留在 handle（未授权不进 decide）。
       /// 注意：这是 static，测试不需实例化 ActionDispatcher（避开 ConfigStore/SerialMonitor 依赖）。
       static func decideAction(cfg: KeyConfig, pressed: Bool) -> Action {
           if pressed {
               switch cfg.type {
               case "cmd":  return .runCmd(cfg.value)
               case "text": return .injectText(cfg.value, enter: cfg.enter ?? true)
               case "key":
                   guard let parsed = KeyInjector.parseKey(cfg.value) else { return .ignore }
                   switch cfg.mode {
                   case "hold": return .pressKey(virtualKey: parsed.virtualKey, modifiers: parsed.modifiers)
                   default:     return .tapKey(virtualKey: parsed.virtualKey, modifiers: parsed.modifiers)
                   }
               default: return .ignore
               }
           } else {
               guard cfg.type == "key", cfg.mode == "hold" else { return .ignore }
               guard let parsed = KeyInjector.parseKey(cfg.value) else { return .ignore }
               return .releaseKey(virtualKey: parsed.virtualKey)
           }
       }
   }
   ```

   `fireDown`/`fireUp` 改成调 `decideAction` 后 switch `Action` 执行副作用（dispatch global、log），**行为不变**（规则9：测试改逻辑会失败；行为对齐 C 阶段实测门）。

   **测试**（参数化覆盖全分支）：
   | pressed | type | mode | value | 期望 Action |
   |---|---|---|---|---|
   | true | cmd | - | "open -a X" | .runCmd |
   | true | text | - | "继续" | .injectText(enter: true) |
   | true | text | - | "x" (enter:nil) | .injectText(enter: true)（默认）|
   | true | key | hold | "option+d" | .pressKey(kVK_ANSI_D, .maskAlternate) |
   | true | key | tap | "ctrl+c" | .tapKey(kVK_ANSI_C, .maskControl) |
   | true | key | nil | "esc" | .tapKey(kVK_Escape, []) |
   | true | key | tap | "zzz" | .ignore（parseKey nil）|
   | true | unknown | - | - | .ignore |
   | false | key | hold | "option+d" | .releaseKey(kVK_ANSI_D) |
   | false | key | tap | "ctrl+c" | .ignore（up 只对 hold）|
   | false | cmd | - | - | .ignore |
   | false | text | - | - | .ignore |
   | false | key | hold | "zzz" | .ignore（parseKey nil）|

### 不测（实测门已覆盖）
- `KeyInjector.tap/press/release`（CGEvent 副作用）—— C 阶段四种动作实测门
- `CmdRunner.run`（Process）—— C 实测 k1
- `TextInjector.inject`（NSPasteboard + KeyInjector）—— C 实测 k2
- `LaunchAtLogin`（SMAppService 系统状态）—— E 实测门
- `SerialMonitor` 的端口/重连/delegate（ORSSerialPort + 硬件）—— B 实测门
- `ActionDispatcher.handle` 的 Accessibility 守门 + 真实 dispatch —— C 实测门；纯分发逻辑由 decideAction 覆盖

//
//  ActionDispatcherTests.swift
//  OpenVibeBoardTests
//
//  阶段 F：ActionDispatcher.decideAction 纯函数测试（全分支参数化）。
//
//  decideAction 是阶段 F 从 fire_down/fire_up 抽出的纯函数：
//    输入 KeyConfig + pressed → 输出 Action 枚举（Equatable 可断言）
//    不查 ConfigStore、不发 CGEvent、不开 Process、不写 log
//
//  全分支覆盖研究表（research/swift-testing.md 测试表 13 行）：
//    pressed × type(cmd/text/key/unknown) × mode(tap/hold/nil) × value(合法/非法)
//
//  副作用执行（CmdRunner/KeyInjector/TextInjector + DispatchQueue）由 C 阶段实测门覆盖。
//

import Testing
import Carbon.HIToolbox
import CoreGraphics
@testable import OpenVibeBoard

@Suite("ActionDispatcher.decideAction")
enum DecideActionTests {

    // MARK: - pressed=true 分支（对照 Python fire_down）

    @Test("down: cmd → runCmd", arguments: [
        "open -a X",
        "echo hi",
    ])
    static func downCmd(value: String) {
        let cfg = KeyConfig(type: "cmd", value: value, mode: "tap", enter: nil, desc: nil)
        let action = ActionDispatcher.decideAction(cfg: cfg, pressed: true)
        #expect(action == .runCmd(value))
    }

    @Test("down: text enter 显式 true")
    static func downTextEnterTrue() {
        let cfg = KeyConfig(type: "text", value: "继续", mode: nil, enter: true, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cfg, pressed: true) == .injectText("继续", enter: true))
    }

    @Test("down: text enter 缺省 → 默认 true（对齐 Python send_text）")
    static func downTextEnterDefault() {
        let cfg = KeyConfig(type: "text", value: "x", mode: nil, enter: nil, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cfg, pressed: true) == .injectText("x", enter: true))
    }

    @Test("down: text enter 显式 false")
    static func downTextEnterFalse() {
        let cfg = KeyConfig(type: "text", value: "x", mode: nil, enter: false, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cfg, pressed: true) == .injectText("x", enter: false))
    }

    @Test("down: key + hold → pressKey（k4 实测门）")
    static func downKeyHold() {
        let cfg = KeyConfig(type: "key", value: "option+d", mode: "hold", enter: nil, desc: nil)
        let action = ActionDispatcher.decideAction(cfg: cfg, pressed: true)
        #expect(action == .pressKey(virtualKey: CGKeyCode(kVK_ANSI_D), modifiers: .maskAlternate))
    }

    @Test("down: key + tap → tapKey（k3 实测门）")
    static func downKeyTap() {
        let cfg = KeyConfig(type: "key", value: "ctrl+c", mode: "tap", enter: nil, desc: nil)
        let action = ActionDispatcher.decideAction(cfg: cfg, pressed: true)
        #expect(action == .tapKey(virtualKey: CGKeyCode(kVK_ANSI_C), modifiers: .maskControl))
    }

    @Test("down: key + mode 缺省 → tapKey（默认 tap）")
    static func downKeyModeNilDefaultsTap() {
        let cfg = KeyConfig(type: "key", value: "esc", mode: nil, enter: nil, desc: nil)
        let action = ActionDispatcher.decideAction(cfg: cfg, pressed: true)
        #expect(action == .tapKey(virtualKey: CGKeyCode(kVK_Escape), modifiers: []))
    }

    @Test("down: key + 非法 value → ignore（parseKey nil）")
    static func downKeyInvalidValue() {
        let cfg = KeyConfig(type: "key", value: "zzz", mode: "tap", enter: nil, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cfg, pressed: true) == .ignore)
    }

    @Test("down: 未知 type → ignore")
    static func downUnknownType() {
        let cfg = KeyConfig(type: "foo", value: "bar", mode: nil, enter: nil, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cfg, pressed: true) == .ignore)
    }

    // MARK: - pressed=false 分支（对照 Python fire_up）

    @Test("up: key + hold → releaseKey（k4 实测门，松开）")
    static func upKeyHoldReleases() {
        let cfg = KeyConfig(type: "key", value: "option+d", mode: "hold", enter: nil, desc: nil)
        let action = ActionDispatcher.decideAction(cfg: cfg, pressed: false)
        #expect(action == .releaseKey(virtualKey: CGKeyCode(kVK_ANSI_D)))
    }

    @Test("up: key + tap → ignore（up 只对 hold）")
    static func upKeyTapIgnored() {
        let cfg = KeyConfig(type: "key", value: "ctrl+c", mode: "tap", enter: nil, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cfg, pressed: false) == .ignore)
    }

    @Test("up: cmd / text → ignore（非 key 类型 up 是 no-op）")
    static func upNonKeyIgnored() {
        let cmdCfg = KeyConfig(type: "cmd", value: "x", mode: nil, enter: nil, desc: nil)
        let textCfg = KeyConfig(type: "text", value: "x", mode: nil, enter: nil, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cmdCfg, pressed: false) == .ignore)
        #expect(ActionDispatcher.decideAction(cfg: textCfg, pressed: false) == .ignore)
    }

    @Test("up: key + hold + 非法 value → ignore（parseKey nil）")
    static func upKeyHoldInvalidValue() {
        let cfg = KeyConfig(type: "key", value: "zzz", mode: "hold", enter: nil, desc: nil)
        #expect(ActionDispatcher.decideAction(cfg: cfg, pressed: false) == .ignore)
    }
}

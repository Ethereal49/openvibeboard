//
//  KeyInjectorTests.swift
//  OpenVibeBoardTests
//
//  阶段 F：KeyInjector.parseKey 参数化测试。
//
//  parseKey 是 KeyInjector 里唯一的纯函数（其余 tap/press/release 是 CGEvent 副作用，
//  由 C 阶段实测门覆盖，见 research/swift-testing.md「不测」清单）。
//  parseKey 是 fileprivate/private 不行——它在 KeyInjector 内部声明为 static，
//  Swift 的 enum static 方法默认 internal，测试 target 可直接调。
//
//  核心断言：单/多 modifier + 别名 / 无 modifier / 特殊键 / 非法。
//  守护 Python spec 的 flags 坑语义（quality-guidelines.md:7-32）——
//  parseKey 错了，CGEvent flags 就错了，整条注入链废。
//

import Testing
import Carbon.HIToolbox
import CoreGraphics
@testable import OpenVibeBoard

@Suite("KeyInjector.parseKey")
enum ParseKeyTests {

    // MARK: - 单 modifier（4 种主 modifier，对齐 Python _FLAG）

    @Test("单 modifier 主名", arguments: [
        ("option+d", CGKeyCode(kVK_ANSI_D), CGEventFlags.maskAlternate),
        ("ctrl+c",   CGKeyCode(kVK_ANSI_C), CGEventFlags.maskControl),
        ("cmd+q",    CGKeyCode(kVK_ANSI_Q), CGEventFlags.maskCommand),
        ("shift+a",  CGKeyCode(kVK_ANSI_A), CGEventFlags.maskShift),
    ])
    static func singleModifier(input: String, vk: CGKeyCode, flags: CGEventFlags) throws {
        let r = try #require(KeyInjector.parseKey(input))
        #expect(r.virtualKey == vk)
        #expect(r.modifiers == flags)
    }

    // MARK: - modifier 别名（对齐 Python _FLAG 的全名/缩写）

    @Test("modifier 别名", arguments: [
        ("control+c", CGEventFlags.maskControl),
        ("command+q", CGEventFlags.maskCommand),
        ("alt+d",     CGEventFlags.maskAlternate),
        ("opt+d",     CGEventFlags.maskAlternate),
    ])
    static func modifierAlias(input: String, flags: CGEventFlags) throws {
        let r = try #require(KeyInjector.parseKey(input))
        #expect(r.modifiers == flags)
    }

    // MARK: - 无 modifier 字母/数字

    @Test("无 modifier 字母/数字 modifiers 为空", arguments: [
        "a", "d", "c", "q", "1", "0",
    ])
    static func noModifier(key: String) throws {
        let r = try #require(KeyInjector.parseKey(key))
        #expect(r.modifiers == [])
        // virtualKey 非 0（kVK_ANSI_* 都 > 0，0 是 kVK_ANSI_A 的反例不成立）
        #expect(r.virtualKey != 0 || key == "a")
    }

    // MARK: - 特殊键

    @Test("特殊键", arguments: [
        ("esc",              kVK_Escape),
        ("escape",           kVK_Escape),
        ("enter",            kVK_Return),
        ("return",           kVK_Return),
        ("space",            kVK_Space),
        ("tab",              kVK_Tab),
        ("up",               kVK_UpArrow),
        ("down",             kVK_DownArrow),
        ("left",             kVK_LeftArrow),
        ("right",            kVK_RightArrow),
        ("delete",           kVK_Delete),
        ("backspace",        kVK_Delete),
    ])
    static func specialKey(name: String, expectedVK: Int) throws {
        let r = try #require(KeyInjector.parseKey(name))
        #expect(r.virtualKey == CGKeyCode(expectedVK))
        #expect(r.modifiers == [])
    }

    // MARK: - 非法（守护 Python 的容错语义：parseKey nil → 分发跳过不崩）

    @Test("非法输入返回 nil", arguments: [
        "xyz",          // 不认识的字符
        "ctrl+zzz",     // modifier 合法但 key 非法
        "foo+bar",      // modifier 非法 + key 非法
        "",             // 空串
    ])
    static func invalid(input: String) {
        #expect(KeyInjector.parseKey(input) == nil)
    }

    // MARK: - 多 modifier（录制器输出的规范格式）

    @Test("多 modifier 组合键")
    static func multiModifierAccepted() throws {
        let r = try #require(KeyInjector.parseKey("cmd+shift+d"))
        #expect(r.virtualKey == CGKeyCode(kVK_ANSI_D))
        #expect(r.modifiers == [.maskCommand, .maskShift])
    }

    @Test("录制事件转规范描述")
    static func descriptorFromEvent() {
        #expect(
            KeyInjector.descriptor(
                for: CGKeyCode(kVK_ANSI_C),
                modifiers: [.maskCommand, .maskShift]
            ) == "cmd+shift+c"
        )
        #expect(
            KeyInjector.descriptor(
                for: CGKeyCode(kVK_Return),
                modifiers: []
            ) == "enter"
        )
    }
}

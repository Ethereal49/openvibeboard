//
//  KeyInjector.swift
//  OpenVibeBoard
//
//  阶段 C：CGEvent 按键注入（核心硬门）。
//
//  逐行复刻 Python vibe_control.py 的 _post / hold_down / hold_up：
//    - _post（vibe_control.py:48-52）：CGEventCreateKeyboardEvent → CGEventSetFlags → CGEventPost
//    - hold_down（:150-161）：char keydown 直接挂 modifier flag（单 modifier 限制）
//    - hold_up（:164-172）：keyup 不带 flag（让系统自动释放 modifier）
//
//  ⚠ CGEvent flags 坑（spec quality-guidelines.md:7-32，跨语言硬约束）：
//  modifier flag 必须挂在 char keydown 上，**禁止单独发 modifier keydown**。
//  违反会导致 modifier 状态残留/字符 repeat（spec 标的最重要坑）。
//  单 modifier 场景纯 .flags 安全（多 modifier 是后续扩展，不在阶段 C 范围）。
//
//  与 Python 的有意偏离（主会话裁决）：
//    tap 也走 CGEvent（合并注入路径）。Python 的 tap 用 osascript 是历史包袱，
//    Swift 不沿用。tap = keydown 立即 keyup（瞬时）；hold = keydown 等松开 keyup。
//

import CoreGraphics
import Carbon.HIToolbox
import Foundation

/// CGEvent 按键注入器。所有方法静默降级（系统资源不足时 CGEvent init 返回 nil，
/// guard let 吞掉，不抛错）—— 对齐 Python HAS_CGEVENT 降级语义。
enum KeyInjector {

    // MARK: - CGEventSource 单例（对齐 Python 模块级 _SRC）

    /// 对应 Python `_SRC = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)`（vibe_control.py:41）。
    ///
    /// `.hidSystemState` 是 HID 系统级状态，能影响所有前台 app。
    /// **不要**用 `.privateState`（只影响本进程，注入到前台 app 不生效）。
    /// `CGEventSource(stateID:)` 是 failable init（极少数情况下返回 nil），
    /// 用 Optional + guard let 优雅降级，比 `!` 强解更稳。
    private static let eventSource: CGEventSource? = CGEventSource(stateID: .hidSystemState)

    // MARK: - 注入接口

    /// tap：瞬时击键，按下立即松开（对应 Python send_key 的"瞬时版"）。
    ///
    /// 与 Python 的差异：Python tap 走 osascript keystroke（Apple Events），
    /// Swift 走 CGEvent（合并到一条注入路径，主会话裁决）。
    /// modifier flag 直接挂在 keydown 上，keyup 不带 flag（让系统自动释放 modifier）。
    static func tap(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
        guard let src = eventSource else { return }
        // keydown 带 flag（核心坑：flag 必须挂这里）
        if let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true) {
            down.flags = modifiers
            down.post(tap: .cghidEventTap)
        }
        // keyup 不带 flag（让系统自动释放 modifier，对应 Python hold_up 的语义）
        if let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }

    /// press：按下并保持（对应 Python hold_down，vibe_control.py:150-161）。
    ///
    /// 中间不 sleep —— WindowServer 没收到 keyup 就认为键还按着，自动维持 modifier 状态。
    /// 用户松开物理键时调 release 配对（对应 Python hold_up）。
    static func press(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
        guard let src = eventSource else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true) {
            down.flags = modifiers          // ★ flag 挂 keydown（核心坑）
            down.post(tap: .cghidEventTap)
        }
    }

    /// release：松开（对应 Python hold_up，vibe_control.py:164-172）。
    ///
    /// **不带 flag**——让系统自动释放 modifier。如果在 keyup 上也挂 .maskAlternate 等，
    /// modifier 状态会泄漏到下一次按键（实测验证，见 Python spec quality-guidelines.md:24-32）。
    static func release(virtualKey: CGKeyCode) {
        guard let src = eventSource else { return }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) {
            // ★ 不要设 .flags——让系统自动释放 modifier
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - key 描述解析（对齐 Python _char_code + _FLAG）

    /// 解析 "option+d" / "ctrl+c" / "esc" / "enter" / "a" 等 → (virtualKey, modifiers)。
    ///
    /// 对齐 Python _char_code（vibe_control.py:144-147）+ hold_down 的 mod split（:153-157）。
    /// **单 modifier 限制**：只支持 `mod+key`，多 modifier（如 `ctrl+shift+d`）是后续扩展
    /// （spec quality-guidelines.md:65 已记录）。
    ///
    /// 返回 nil 表示 key 描述无法识别（运行时分发器会 log + 跳过，不崩）。
    static func parseKey(_ key: String) -> (virtualKey: CGKeyCode, modifiers: CGEventFlags)? {
        // 拆 modifier（与 Python key.split("+", 1) 对齐，只取第一个 +）
        if let plusIdx = key.firstIndex(of: "+") {
            let modStr = String(key[..<plusIdx]).lowercased()
            let charStr = String(key[key.index(after: plusIdx)...]).lowercased()

            guard let modFlag = modifierFlag(modStr) else {
                return nil
            }
            guard let vk = charKeyCode(charStr) else {
                return nil
            }
            return (CGKeyCode(vk), modFlag)
        }

        // 无 modifier：查 KEY_CODES（特殊键/数字）或 CHAR_CODES（字母数字）
        let k = key.lowercased()
        guard let vk = specialKeyCode(k) ?? charKeyCode(k) else {
            return nil
        }
        return (CGKeyCode(vk), [])
    }

    // MARK: - modifier 名 → CGEventFlags（对齐 Python _FLAG，vibe_control.py:43-46）

    private static func modifierFlag(_ name: String) -> CGEventFlags? {
        switch name {
        case "ctrl", "control":     return .maskControl
        case "cmd", "command":      return .maskCommand
        case "shift":               return .maskShift
        case "option", "alt", "opt": return .maskAlternate
        default:                    return nil
        }
    }

    // MARK: - 字符 → virtualKey（对齐 Python CHAR_CODES，vibe_control.py:73-79）

    /// 用 Carbon kVK_ANSI_* 符号常量（HIToolbox/Events.h），不硬编码 magic number。
    /// 注意：kVK_ANSI_* 是 US QWERTY 布局的物理键位（与 Python CHAR_CODES 同源）。
    private static func charKeyCode(_ ch: String) -> Int? {
        switch ch {
        case "a": return kVK_ANSI_A
        case "s": return kVK_ANSI_S
        case "d": return kVK_ANSI_D
        case "f": return kVK_ANSI_F
        case "h": return kVK_ANSI_H
        case "g": return kVK_ANSI_G
        case "z": return kVK_ANSI_Z
        case "x": return kVK_ANSI_X
        case "c": return kVK_ANSI_C
        case "v": return kVK_ANSI_V
        case "b": return kVK_ANSI_B
        case "q": return kVK_ANSI_Q
        case "w": return kVK_ANSI_W
        case "e": return kVK_ANSI_E
        case "r": return kVK_ANSI_R
        case "y": return kVK_ANSI_Y
        case "t": return kVK_ANSI_T
        case "1": return kVK_ANSI_1
        case "2": return kVK_ANSI_2
        case "3": return kVK_ANSI_3
        case "4": return kVK_ANSI_4
        case "5": return kVK_ANSI_5
        case "6": return kVK_ANSI_6
        case "7": return kVK_ANSI_7
        case "8": return kVK_ANSI_8
        case "9": return kVK_ANSI_9
        case "0": return kVK_ANSI_0
        case "o": return kVK_ANSI_O
        case "u": return kVK_ANSI_U
        case "i": return kVK_ANSI_I
        case "p": return kVK_ANSI_P
        case "l": return kVK_ANSI_L
        case "j": return kVK_ANSI_J
        case "k": return kVK_ANSI_K
        case "n": return kVK_ANSI_N
        case "m": return kVK_ANSI_M
        case " ": return kVK_Space
        default: return nil
        }
    }

    // MARK: - 特殊键名 → virtualKey（对齐 Python KEY_CODES，vibe_control.py:70-72）

    /// 特殊键与方向键。Python KEY_CODES 是硬编码数字表，Swift 用 kVK_* 符号常量。
    private static func specialKeyCode(_ name: String) -> Int? {
        switch name {
        case "esc", "escape": return kVK_Escape
        case "tab":           return kVK_Tab
        case "enter", "return": return kVK_Return
        case "space":         return kVK_Space
        case "delete", "backspace": return kVK_Delete
        case "up":            return kVK_UpArrow
        case "down":          return kVK_DownArrow
        case "left":          return kVK_LeftArrow
        case "right":         return kVK_RightArrow
        // modifier 单独按（无 char）—— hold_down 的 else 分支会查这里（vibe_control.py:158-160）。
        // 但 menu bar app 场景几乎不会配置"按住单独 option"，且单独发 modifier keydown
        // 容易踩 flags 坑（spec 明确禁止），所以这里**不暴露** modifier 单键。
        default: return nil
        }
    }
}

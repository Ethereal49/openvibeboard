//
//  KeyInjector.swift
//  OpenVibeBoard
//
//  阶段 C：CGEvent 按键注入（核心硬门）。
//
//  逐行复刻 Python vibe_control.py 的 _post / hold_down / hold_up：
//    - _post（vibe_control.py:48-52）：CGEventCreateKeyboardEvent → CGEventSetFlags → CGEventPost
//    - hold_down（:150-161）：char keydown 直接挂 modifier flags
//    - hold_up（:164-172）：keyup 不带 flag（让系统自动释放 modifier）
//
//  ⚠ CGEvent flags 坑（spec quality-guidelines.md:7-32，跨语言硬约束）：
//  modifier flag 必须挂在 char keydown 上，**禁止单独发 modifier keydown**。
//  违反会导致 modifier 状态残留/字符 repeat（spec 标的最重要坑）。
//  多 modifier 同样合并到 char keydown 的 flags，禁止拆成独立 modifier 事件。
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
    /// 支持一个或多个 modifier（如 `cmd+shift+d`）。最后一段必须是实际按键。
    ///
    /// 返回 nil 表示 key 描述无法识别（运行时分发器会 log + 跳过，不崩）。
    static func parseKey(_ key: String) -> (virtualKey: CGKeyCode, modifiers: CGEventFlags)? {
        let parts = key
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }

        if parts.count > 1 {
            guard let charStr = parts.last, !charStr.isEmpty,
                  let vk = specialKeyCode(charStr) ?? charKeyCode(charStr) else {
                return nil
            }

            var flags: CGEventFlags = []
            for modifier in parts.dropLast() {
                guard let modFlag = modifierFlag(modifier) else { return nil }
                flags.insert(modFlag)
            }
            return (CGKeyCode(vk), flags)
        }

        // 无 modifier：查 KEY_CODES（特殊键/数字）或 CHAR_CODES（字母数字）
        let k = key.lowercased()
        guard let vk = specialKeyCode(k) ?? charKeyCode(k) else {
            return nil
        }
        return (CGKeyCode(vk), [])
    }

    // MARK: - 反向：virtualKey + modifiers → 可读符号（Settings 预览用）

    /// 把 (virtualKey, modifiers) 反向渲染成 macOS 习惯的可读符号串，如 `⌃C` / `⌥D` / `⎋` / `↩`。
    ///
    /// 与 `parseKey` 互为镜像：parse 正向（描述串 → virtualKey+flags），label 反向。
    /// 放在 KeyInjector 同 enum 命名空间，复用 charKeyCode/specialKeyCode 的反向查表。
    ///
    /// 纯函数（无 IO / 无 actor），便于后续在 test target 直接断言（F 阶段测试风格）。
    ///
    /// modifier 顺序固定 ⌃⌥⇧⌘（系统偏好设置 → 键盘快捷键里的标准顺序），避免用户输入
    /// `ctrl+shift` 与 `shift+ctrl` 渲染出不同串。
    static func label(for virtualKey: CGKeyCode, modifiers: CGEventFlags) -> String {
        var s = ""
        // modifier 按系统标准顺序拼接
        if modifiers.contains(.maskControl)  { s += "⌃" }
        if modifiers.contains(.maskAlternate) { s += "⌥" }
        if modifiers.contains(.maskShift)     { s += "⇧" }
        if modifiers.contains(.maskCommand)   { s += "⌘" }
        s += charSymbol(for: Int(virtualKey)) ?? "?"
        return s
    }

    /// 把录制到的 virtual key 和 modifier 转成可持久化的规范描述。
    /// UI 录制器只负责采集事件，解析和持久化格式仍由 KeyInjector 统一拥有。
    static func descriptor(for virtualKey: CGKeyCode, modifiers: CGEventFlags) -> String? {
        guard let key = keyName(for: Int(virtualKey)) else { return nil }
        var parts: [String] = []
        if modifiers.contains(.maskCommand) { parts.append("cmd") }
        if modifiers.contains(.maskControl) { parts.append("ctrl") }
        if modifiers.contains(.maskAlternate) { parts.append("option") }
        if modifiers.contains(.maskShift) { parts.append("shift") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// virtualKey → 可读字符/符号的反向映射（charKeyCode/specialKeyCode 的反向表）。
    ///
    /// 字母键大写显示（macOS 习惯：⌃C 而非 ⌃c），数字键原样，特殊键用 Unicode 符号。
    /// 不识别的 vk 返回 nil（label 里降级为 "?"）。
    ///
    /// 反向表为什么手写而不复用 charKeyCode：charKeyCode 是 String→Int 单向，
    /// 反向需要 Int→String，且字母要 uppercase、特殊键要符号（不是 "esc"/"return" 字面），
    /// 语义不同，独立维护更清晰。
    private static func charSymbol(for vk: Int) -> String? {
        // 特殊键优先（kVK_Space 也属于这里）
        if let sym = specialKeySymbol(vk) { return sym }
        // 字母数字：用 kVK_ANSI_* 反向
        let letterMap: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_S: "S", kVK_ANSI_D: "D", kVK_ANSI_F: "F",
            kVK_ANSI_H: "H", kVK_ANSI_G: "G", kVK_ANSI_Z: "Z", kVK_ANSI_X: "X",
            kVK_ANSI_C: "C", kVK_ANSI_V: "V", kVK_ANSI_B: "B", kVK_ANSI_Q: "Q",
            kVK_ANSI_W: "W", kVK_ANSI_E: "E", kVK_ANSI_R: "R", kVK_ANSI_Y: "Y",
            kVK_ANSI_T: "T", kVK_ANSI_O: "O", kVK_ANSI_U: "U", kVK_ANSI_I: "I",
            kVK_ANSI_P: "P", kVK_ANSI_L: "L", kVK_ANSI_J: "J", kVK_ANSI_K: "K",
            kVK_ANSI_N: "N", kVK_ANSI_M: "M",
            kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
            kVK_ANSI_9: "9", kVK_ANSI_0: "0",
        ]
        return letterMap[vk]
    }

    private static func keyName(for vk: Int) -> String? {
        switch vk {
        case kVK_Escape: return "esc"
        case kVK_Return: return "enter"
        case kVK_Space: return "space"
        case kVK_Tab: return "tab"
        case kVK_Delete: return "delete"
        case kVK_UpArrow: return "up"
        case kVK_DownArrow: return "down"
        case kVK_LeftArrow: return "left"
        case kVK_RightArrow: return "right"
        default: break
        }

        let names: [Int: String] = [
            kVK_ANSI_A: "a", kVK_ANSI_S: "s", kVK_ANSI_D: "d", kVK_ANSI_F: "f",
            kVK_ANSI_H: "h", kVK_ANSI_G: "g", kVK_ANSI_Z: "z", kVK_ANSI_X: "x",
            kVK_ANSI_C: "c", kVK_ANSI_V: "v", kVK_ANSI_B: "b", kVK_ANSI_Q: "q",
            kVK_ANSI_W: "w", kVK_ANSI_E: "e", kVK_ANSI_R: "r", kVK_ANSI_Y: "y",
            kVK_ANSI_T: "t", kVK_ANSI_O: "o", kVK_ANSI_U: "u", kVK_ANSI_I: "i",
            kVK_ANSI_P: "p", kVK_ANSI_L: "l", kVK_ANSI_J: "j", kVK_ANSI_K: "k",
            kVK_ANSI_N: "n", kVK_ANSI_M: "m", kVK_ANSI_1: "1", kVK_ANSI_2: "2",
            kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6",
            kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0"
        ]
        return names[vk]
    }

    /// 特殊键 virtualKey → Unicode 符号。
    /// 单独成函数：与 specialKeyCode（正向 String→Int）解耦，因符号是展示语义而非解析语义。
    private static func specialKeySymbol(_ vk: Int) -> String? {
        switch vk {
        case kVK_Escape:     return "⎋"
        case kVK_Return:     return "↩"
        case kVK_Space:      return "␣"
        case kVK_Tab:        return "⇥"
        case kVK_Delete:     return "⌫"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        default:             return nil
        }
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

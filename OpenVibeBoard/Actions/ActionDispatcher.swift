//
//  ActionDispatcher.swift
//  OpenVibeBoard
//
//  阶段 C：动作分发器。
//
//  逐行对照 Python vibe_control.py 的 fire_down（:175-197）/ fire_up（:199-206）：
//    - cmd  → CmdRunner.run          (subprocess.Popen 非阻塞)
//    - text → TextInjector.inject    (NSPasteboard + Cmd+V + 可选 Enter)
//    - key tap  → KeyInjector.tap    (keydown 立即 keyup，瞬时)
//    - key hold press → KeyInjector.press  (keydown 等 release)
//    - key hold release → KeyInjector.release (keyup)
//
//  分发链与 Python 对齐（directory-structure.md 的分发链）：
//    serial button event → ActionDispatcher.dispatch(event)
//                         → 查 ConfigStore[button]
//                         → 按 cfg.type/mode 分发到 KeyInjector/CmdRunner/TextInjector
//
//  与 Python 的有意偏离（主会话裁决，非 bug）：
//    1. tap 也走 CGEvent（合并注入路径），不走 osascript keystroke
//    2. CGEvent 重活 / Process 在 global queue 跑（SerialMonitor delegate 在 main queue，
//       不能同步做重活卡 UI，见 orsserialport.md:282-288）
//    3. 守护不崩：CGEvent/Process 失败 try? + log（对齐 Python HAS_* 降级）
//

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

@MainActor
final class ActionDispatcher: ObservableObject {

    /// 未授权 Accessibility 时菜单栏提示用。
    @Published private(set) var lastDeniedAt: Date?

    private var cancellables = Set<AnyCancellable>()
    private let config: ConfigStore

    init(serial: SerialMonitor, config: ConfigStore = .shared) {
        self.config = config
        // 订阅 SerialMonitor.buttonEvents（PassthroughSubject）。
        // 阶段 B 已建好；这里订阅后做分发。
        serial.buttonEvents
            .sink { [weak self] event in
                Task { await self?.handle(event) }
            }
            .store(in: &cancellables)
    }

    // MARK: - 事件入口（@MainActor，从 PassthroughSubject 回调进入）

    /// 处理一次按键事件（down/up）。
    ///
    /// 对齐 Python serial_loop 解析后调 fire_down/fire_up。
    /// 重活（CGEvent/Process）dispatch 到 global queue，不在 main queue 同步做（卡 UI）。
    private func handle(_ event: ButtonEvent) async {
        let cfg = await config.snapshot()[event.button]
        guard let cfg = cfg else { return }

        let desc = cfg.desc ?? cfg.value

        // Accessibility 守门：未授权则 log + 提示，不发任何 CGEvent
        // （未授权时 CGEvent.post 不抛错但目标 app 收不到事件，所以先检查避免无效操作）
        guard Accessibility.isTrusted else {
            lastDeniedAt = Date()
            ActionDispatcher.log("⚠️ 未授权辅助功能，\(event.button) \(event.pressed ? "▼" : "▲") 已忽略")
            return
        }

        // down/up 都进入，分支内部按 pressed + cfg.type/mode 决定
        if event.pressed {
            await fireDown(button: event.button, cfg: cfg, desc: desc)
        } else {
            await fireUp(button: event.button, cfg: cfg)
        }
    }

    // MARK: - fire_down（对照 Python vibe_control.py:175-197）

    private func fireDown(button: String, cfg: KeyConfig, desc: String) async {
        switch cfg.type {
        case "cmd":
            // 对应 Python run_cmd（:106-108）：subprocess.Popen 非阻塞
            ActionDispatcher.log("\(button) -> \(desc)")
            let value = cfg.value
            DispatchQueue.global(qos: .userInitiated).async {
                CmdRunner.run(value)
            }

        case "text":
            // 对应 Python send_text（:131-141）：pbcopy + Cmd+V + 可选 enter
            ActionDispatcher.log("\(button) -> 输入文本 \(desc)")
            let value = cfg.value
            let enter = cfg.enter ?? true
            DispatchQueue.global(qos: .userInitiated).async {
                TextInjector.inject(value, enter: enter)
            }

        case "key":
            // 对应 Python fire_down 的 key 分支（:187-196）
            switch cfg.mode {
            case "hold":
                let value = cfg.value
                ActionDispatcher.log("\(button) ▼ 按住 \(value)")
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let parsed = KeyInjector.parseKey(value) else {
                        ActionDispatcher.log("⚠️ 无法解析 key: \(value)")
                        return
                    }
                    KeyInjector.press(virtualKey: parsed.virtualKey, modifiers: parsed.modifiers)
                }
            default:  // "tap" 或未指定
                let value = cfg.value
                ActionDispatcher.log("\(button) -> \(desc)")
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let parsed = KeyInjector.parseKey(value) else {
                        ActionDispatcher.log("⚠️ 无法解析 key: \(value)")
                        return
                    }
                    KeyInjector.tap(virtualKey: parsed.virtualKey, modifiers: parsed.modifiers)
                }
            }

        default:
            ActionDispatcher.log("⚠️ 未知 type: \(cfg.type)")
        }
    }

    // MARK: - fire_up（对照 Python vibe_control.py:199-206）

    /// 对应 Python fire_up：只有 key+hold 才需要在 up 时做事（release）。
    /// 其他类型 up 是 no-op（Python 同样如此）。
    private func fireUp(button: String, cfg: KeyConfig) async {
        guard cfg.type == "key", cfg.mode == "hold" else { return }
        let value = cfg.value
        ActionDispatcher.log("\(button) ▲ 释放")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let parsed = KeyInjector.parseKey(value) else {
                ActionDispatcher.log("⚠️ 无法解析 key: \(value)")
                return
            }
            KeyInjector.release(virtualKey: parsed.virtualKey)
        }
    }

    // MARK: - 日志（对齐 Python log() "[HH:MM:SS] msg" 格式 + flush）

    private static func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }
}

// MARK: - CmdRunner（对应 Python run_cmd，vibe_control.py:106-108）

/// 异步执行 shell 命令，不阻塞调用线程。
///
/// **必须非阻塞**（spec quality-guidelines.md）：调 `Process.run()`（异步启动后立即返回，
/// 等价 subprocess.Popen），不调 `waitUntilExit()`（会卡串口/main 线程）。
///
/// **sandbox 限制**：sandboxed app 的 Process.run("/bin/sh -c ...") 默认只能执行
/// /bin /usr/bin 下的系统二进制。config.json 的 k1=`open -a Codex`（/usr/bin/open）✅
/// 不受影响。用户自定义脚本路径可能被拒（主会话裁决：不预防性加 entitlement）。
enum CmdRunner {
    static func run(_ cmd: String) {
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", cmd]
        // stdout/stderr 丢弃（对齐 Python subprocess.DEVNULL）
        p.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        p.standardError = FileHandle(forWritingAtPath: "/dev/null")
        // try? + log，永不抛到上游（spec error-handling.md「守护进程不崩」）
        do {
            try p.run()
        } catch {
            NSLog("[OpenVibeBoard] cmd 执行失败: \(cmd) — \(error.localizedDescription)")
        }
    }
}

// MARK: - TextInjector（对应 Python send_text，vibe_control.py:131-141）

/// 剪贴板方案：NSPasteboard + Cmd+V，绕过输入法对中文的不确定性。
///
/// 对齐 Python send_text 的设计（quality-guidelines.md「文本输入动作」）：
///    - 为什么不用 keystroke：依赖当前输入法，中文模式下可能触发拼音
///    - pbcopy + Cmd+V 直接粘贴字符，绕过输入法，对中文最可靠
///    - 副作用：覆盖一次剪贴板内容（快捷键场景可接受，刻意不保存/恢复）
///
/// Swift 比 Python 干净：NSPasteboard.general.clearContents + setString，
/// 不需要 pbcopy subprocess。
enum TextInjector {
    static func inject(_ text: String, enter: Bool = true) {
        // 1. 写剪贴板（必须先 clearContents 再 setString，否则会追加而不是替换）
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // 2. 发 Cmd+V（keyCode kVK_ANSI_V，flag .maskCommand）
        KeyInjector.tap(virtualKey: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)

        // 3. 可选 Enter，等 paste 事件落地（对齐 Python time.sleep(0.05)）
        if enter {
            Thread.sleep(forTimeInterval: 0.05)
            KeyInjector.tap(virtualKey: CGKeyCode(kVK_Return))
        }
    }
}

//
//  MenuBarView.swift
//  OpenVibeBoard
//
//  阶段 A 占位菜单。后续阶段（B/C/D/E）填充真实状态/开关/串口连接信息。
//
//  阶段 B：菜单显示串口连接状态 + 最近一次按键事件，让监听可观测、可实测。
//  阶段 C：菜单显示 Accessibility 授权状态（未授权时红色提示 + 一键重试弹窗）。
//  阶段 D：加「打开设置…」项，调起 SwiftUI Settings 场景窗口。
//  阶段 E：加「开机自启」Toggle，调 SMAppService 注册/取消登录项。
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var serial: SerialMonitor
    @EnvironmentObject private var dispatcher: ActionDispatcher
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // 阶段 C：Accessibility 授权状态（CGEvent 注入的唯一前置）。
        // 未授权时红色提示（对齐 Python HAS_* 降级 + 菜单图标状态提示的语义）。
        if !Accessibility.isTrusted {
            VStack(alignment: .leading, spacing: 2) {
                Text("辅助功能权限未开启")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("快捷键和文本动作无法执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("打开授权设置…") {
                    Accessibility.openSystemSettings()
                }
            }
            Divider()
        }

        // 阶段 B：串口连接状态 + 最近事件（观测门）。
        VStack(alignment: .leading, spacing: 2) {
            Label(
                serial.status == .connected ? "键盘已连接" : "键盘\(serial.status.rawValue)",
                systemImage: serial.status == .connected ? "checkmark.circle.fill" : "keyboard.badge.ellipsis"
            )
            if let err = serial.lastError, serial.status == .error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if let ev = serial.lastEvent {
                Text("最近按键：\(ev.button) \(ev.pressed ? "按下" : "松开")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("等待物理按键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        // 阶段 E：开机自启 Toggle（SMAppService）。
        // 用 computed binding：getter 每次菜单 render 时查 SMAppService.mainApp.status，
        // 不缓存（用户可能在「系统设置 → 登录项」改过，缓存会显示陈旧勾选态）。
        // setter 走 LaunchAtLogin.toggle()，再据返回值刷新。
        Toggle("开机自启", isOn: Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { _ in
                _ = LaunchAtLogin.toggle()
            }
        ))

        // 阶段 D：打开 Settings 场景窗口。
        // macOS 14+ 用 SwiftUI 官方的 EnvironmentValues.openSettings（SettingsLink 同源）。
        // 实测：旧的 NSApp.sendAction(showSettingsWindow:) selector 在 macOS 26 上返回 true
        // 但**不真正打开** Settings 窗口（仅创建状态栏图标窗口，非 Settings）——Apple 已弃用该路径。
        // deployment target 因此从 13 提到 14（用户系统 macOS 26，13 无意义），用官方 openSettings。
        Button("打开设置…") {
            openSettings()
            // menu bar app (LSUIElement) 不在前台时，openSettings 会 orderFront Settings 窗口
            // 但不抢焦点（窗口出现在其它 app 后面 / 不带前台激活）。
            // NSApp.activate() 把本进程拉到前台，让 Settings 窗口真正可见可输入。
            // macOS 14+ 无参版（deployment 14 ✓）；老 NSApplication.activate(ignoringOtherApps:)
            // 已被无参 activate() 取代。
            NSApp.activate()
        }
        .keyboardShortcut(",")

        Button("关于 OpenVibeBoard") {
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Divider()

        Button("退出 OpenVibeBoard") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

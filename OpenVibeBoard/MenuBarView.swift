//
//  MenuBarView.swift
//  OpenVibeBoard
//
//  阶段 A 占位菜单。后续阶段（B/C/D/E）填充真实状态/开关/串口连接信息。
//
//  阶段 B：菜单显示串口连接状态 + 最近一次按键事件，让监听可观测、可实测。
//  阶段 C：菜单显示 Accessibility 授权状态（未授权时红色提示 + 一键重试弹窗）。
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var serial: SerialMonitor
    @EnvironmentObject private var dispatcher: ActionDispatcher

    var body: some View {
        // 阶段 C：Accessibility 授权状态（CGEvent 注入的唯一前置）。
        // 未授权时红色提示（对齐 Python HAS_* 降级 + 菜单图标状态提示的语义）。
        if !Accessibility.isTrusted {
            VStack(alignment: .leading, spacing: 2) {
                Text("⚠️ 未授权辅助功能")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("CGEvent 按键注入将静默失效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("重新请求授权") {
                    Accessibility.ensure()
                }
            }
            Divider()
        }

        // 阶段 B：串口连接状态 + 最近事件（观测门）。
        VStack(alignment: .leading, spacing: 2) {
            Text("状态：\(serial.status.rawValue)")
            if let err = serial.lastError, serial.status == .error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if let ev = serial.lastEvent {
                Text("最近事件：\(ev.button) \(ev.pressed ? "▼" : "▲")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("最近事件：（等待物理按键）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        Button("关于 OpenVibeBoard") {
            // 阶段 A 占位；阶段 D/E 接 NSApp.orderFrontStandardAboutPanel(nil)。
        }

        Divider()

        Button("退出 OpenVibeBoard") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

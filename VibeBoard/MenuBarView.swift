//
//  MenuBarView.swift
//  VibeBoard
//
//  阶段 A 占位菜单。后续阶段（B/C/D/E）填充真实状态/开关/串口连接信息。
//

import SwiftUI

struct MenuBarView: View {
    var body: some View {
        // 占位：阶段 A 不接业务逻辑，按钮先空 action。
        Text("状态：开发中")

        Divider()

        Button("关于 VibeBoard") {
            // 阶段 A 占位；阶段 D/E 接 NSApp.orderFrontStandardAboutPanel(nil)。
        }

        Divider()

        Button("退出 VibeBoard") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

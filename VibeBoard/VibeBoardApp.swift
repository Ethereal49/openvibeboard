//
//  VibeBoardApp.swift
//  VibeBoard
//
//  Swift 原生 macOS 状态栏 app（v0.2.0）。
//  阶段 A：MenuBarExtra 单 scene 占位菜单 + Config 持久化。
//  阶段 B：接入 SerialMonitor（ORSSerialPort 串口监听），菜单显示按键事件。
//

import SwiftUI

@main
struct VibeBoardApp: App {
    // 阶段 A 用单 scene；阶段 D 再加 Settings。
    //
    // 启动即触发 ConfigStore.shared.load()：首启写默认配置到 Application Support，
    // 已有配置则加载到内存。后续阶段（B 串口读 / D Settings 写）共用同一 actor 实例。
    //
    // 阶段 B：SerialMonitor 在 @StateObject 构造时（init 后下一个 main runloop）自动 start()，
    // 开始监听 /dev/cu.usbmodem3101。这里只持引用 + 注入到 MenuBarView。
    @StateObject private var serial = SerialMonitor()

    init() {
        Task.detached(priority: .utility) {
            _ = await ConfigStore.shared.load()
        }
    }

    var body: some Scene {
        MenuBarExtra("VibeBoard", systemImage: "keyboard") {
            MenuBarView()
                .environmentObject(serial)
        }
        .menuBarExtraStyle(.menu)
    }
}

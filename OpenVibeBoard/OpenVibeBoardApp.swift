//
//  OpenVibeBoardApp.swift
//  OpenVibeBoard
//
//  Swift 原生 macOS 状态栏 app（v0.2.0）。
//  阶段 A：MenuBarExtra 单 scene 占位菜单 + Config 持久化。
//  阶段 B：接入 SerialMonitor（ORSSerialPort 串口监听），菜单显示按键事件。
//  阶段 C：接入 ActionDispatcher（CGEvent 按键注入），Accessibility 权限守门。
//

import SwiftUI

@main
struct OpenVibeBoardApp: App {
    // 阶段 A 用单 scene；阶段 D 再加 Settings。
    //
    // 启动即触发 ConfigStore.shared.load()：首启写默认配置到 Application Support，
    // 已有配置则加载到内存。后续阶段（B 串口读 / D Settings 写）共用同一 actor 实例。
    //
    // 阶段 B：SerialMonitor 在 @StateObject 构造时（init 后下一个 main runloop）自动 start()，
    // 开始监听 /dev/cu.usbmodem3101。这里只持引用 + 注入到 MenuBarView。
    //
    // 阶段 C：ActionDispatcher 订阅 serial.buttonEvents，按 config 分发按键到
    // CmdRunner / TextInjector / KeyInjector。ActionDispatcher 作为 @StateObject 注入
    // MenuBarView，便于展示「未授权」状态提示。
    @StateObject private var serial = SerialMonitor()
    @StateObject private var dispatcher: ActionDispatcher

    init() {
        // SerialMonitor 必须先存在，再传给 ActionDispatcher 订阅 buttonEvents。
        // SwiftUI 的 @StateObject 包装要求在 super.init 前用 _xxx = StateObject(wrappedValue:)
        // 初始化，但两个 @StateObject 之间有依赖时，直接构造 wrappedValue 即可。
        let serialHolder = SerialMonitor()
        _serial = StateObject(wrappedValue: serialHolder)
        _dispatcher = StateObject(wrappedValue: ActionDispatcher(serial: serialHolder))

        Task.detached(priority: .utility) {
            _ = await ConfigStore.shared.load()
        }

        // 阶段 C：启动后 menu bar 图标已显示（MenuBarExtra scene 已挂载），
        // 但物理按键第一次触发前，主动弹一次 Accessibility 授权对话框。
        // Task.detached 不阻塞 UI；Accessibility.ensure() 内部调
        // AXIsProcessTrustedWithOptions 异步弹系统对话框。
        Task.detached(priority: .utility) {
            _ = Accessibility.ensure()
        }
    }

    var body: some Scene {
        MenuBarExtra("OpenVibeBoard", systemImage: "keyboard") {
            MenuBarView()
                .environmentObject(serial)
                .environmentObject(dispatcher)
        }
        .menuBarExtraStyle(.menu)
    }
}

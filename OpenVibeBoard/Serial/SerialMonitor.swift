//
//  SerialMonitor.swift
//  OpenVibeBoard
//
//  阶段 B：串口监听（ORSSerialPort）。
//
//  复刻 Python vibe_control.py 的 serial_loop() 语义（vibe_control.py:209-230）：
//    - 开 /dev/cu.usbmodem3101（PORT_SERIAL），115200（BAUD）
//    - 按行解析 "button (down|up) (k\d+)"，匹配则发 ButtonEvent
//    - 串口异常（占用/拔除/缺权限）→ 打日志 + 5 秒后重连，守护进程不崩
//
//  与 Python 的差异（见 .trellis/tasks/07-04-swift-menubar-app/research/orsserialport.md）：
//    1. ORSSerialPort 自带 packet parser（ORSSerialPacketDescriptor + 正则），不需手写 buf += chunk 切行
//    2. ORSSerialPortDelegate 全部方法在 main queue 回调（ORSSerialPort.h:567 注释明确），
//       更新 SwiftUI 状态不用切线程；重活（CGEvent/subprocess，阶段 C 才做）届时再 dispatch global
//    3. open() 不返回 Bool，失败走 serialPort(_:didEncounterError:) delegate
//

import Foundation
import ORSSerial
import Combine

/// 按键事件（解析后的 high-level 形态）。
///
/// 等价于 Python serial_loop 里 DOWN_RE/UP_RE 匹配出的 (button, pressed) 元组。
/// 下游（MenuBarView 阶段 B；ActionDispatcher 阶段 C）订阅 SerialMonitor.buttonEvents。
struct ButtonEvent: Equatable {
    let button: String      // "k1" / "k3" ...
    let pressed: Bool       // down=true, up=false
}

/// 串口监听器（@MainActor：delegate 全在 main queue 回调，直接更新 SwiftUI 状态）。
///
/// 对齐 Python serial_loop 的"守护进程不崩"语义：
/// 端口打开失败 / 运行中出错 / 设备被拔 → 仅打日志 + 重连，不抛异常。
@MainActor
final class SerialMonitor: NSObject, ObservableObject, ORSSerialPortDelegate {

    // MARK: - 常量（对齐 Python）

    /// 对齐 Python PORT_SERIAL（vibe_control.py:63）。
    static let path = "/dev/cu.usbmodem3101"

    /// 对齐 Python BAUD = 115200（vibe_control.py:64）。
    /// ORSSerialPort 的 baudRate 是 NSNumber，这里用 Int 常量存，赋值时转 NSNumber。
    static let baudRate: Int = 115200

    /// 重连间隔（复刻 Python 的"循环重试"语义；这里固定 5 秒避免 spin）。
    private static let reconnectDelay: TimeInterval = 5

    /// 同时吃 down/up，capture group 区分。对齐 Python DOWN_RE/UP_RE（vibe_control.py:81-82）。
    ///
    /// `nonisolated`：NSRegularExpression 是 immutable 线程安全，构造一次全局共用。
    /// 阶段 F：parseLine 是 nonisolated 纯函数，访问此 pattern 需它也 nonisolated。
    nonisolated private static let linePattern: NSRegularExpression = {
        // 静态构造，避免每次匹配重编译。
        // pattern 与 ORSSerialPacketDescriptor 共用，delegate 里再用同一 pattern 提 capture group。
        // \d+ 容纳 k10+（固件理论上可多于 9 个键；Python 用 \d，此处宽松对齐未来）。
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: "button (down|up) (k\\d+)")
    }()

    /// 纯函数：把一行串口文本解析成 ButtonEvent（阶段 F 抽出，便于单测）。
    ///
    /// 抽离自 `serialPort(_:didReceivePacket:matchingDescriptor:)`：descriptor 只保证整包匹配
    /// linePattern，不拆 capture group，所以仍需自己再 match 一次。把这段提取出来后：
    ///   - delegate 改调它（行为不变）
    ///   - 测试可覆盖 `"button down k3"` / `"button up k12"`（\d+ 容纳 k10+）/ 非法 / 缺数字
    ///
    /// `nonisolated`：虽然 SerialMonitor 是 @MainActor，parseLine 只读 static 正则 + 纯字符串操作，
    /// 不触任何 main actor 状态，标 nonisolated 让测试在 nonisolated 上下文直接调，无需 async/await。
    nonisolated static func parseLine(_ line: String) -> ButtonEvent? {
        // 提 capture group（descriptor 不会把 group 拆开给你，要自己再 match 一次）。
        let match = linePattern.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        )
        guard let match = match, match.numberOfRanges >= 3 else { return nil }

        guard
            let pressedRange = Range(match.range(at: 1), in: line),
            let buttonRange  = Range(match.range(at: 2), in: line)
        else { return nil }

        let pressed = line[pressedRange] == "down"
        let button  = String(line[buttonRange])

        return ButtonEvent(button: button, pressed: pressed)
    }

    // MARK: - 状态

    /// 当前连接状态（UI 显示用）。
    enum Status: String {
        case disconnected = "未连接"
        case connecting    = "连接中"
        case connected     = "已连接"
        case error         = "错误"        // 附带 lastError 描述
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var lastEvent: ButtonEvent?       // 最近一次按键事件（菜单显示用）
    @Published private(set) var lastError: String?            // 最近一次错误描述

    /// 给下游订阅的按键事件流（阶段 B 仅 MenuBarView 订阅做展示；阶段 C ActionDispatcher 订阅做分发）。
    let buttonEvents = PassthroughSubject<ButtonEvent, Never>()

    private var port: ORSSerialPort?
    private let lineDescriptor: ORSSerialPacketDescriptor
    private var reconnectWorkItem: DispatchWorkItem?
    private var isStarted = false

    // MARK: - init

    override init() {
        // maximumPacketLength：单包字节硬上限。"button down k12\n" ≈ 18 字节，填 64 留足余量。
        // 见 research note #7：填太小会丢 k10+ 的包；填 0/1 完全不可用。
        lineDescriptor = ORSSerialPacketDescriptor(
            regularExpression: SerialMonitor.linePattern,
            maximumPacketLength: 64,
            userInfo: nil
        )
        super.init()
        // 阶段 B：构造即启动。注意：MenuBarExtra 菜单内容的 onAppear 直到用户点开菜单才触发，
        // 串口监听不能等那时；这里在 init 后下一个 main runloop 立刻 open。
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    // MARK: - 生命周期

    /// 启动监听（幂等：port 已存在则不重复 open）。
    ///
    /// 复刻 Python serial_loop 的"启动即开"语义。失败（端口不存在 / EBUSY / EPERM）
    /// 不抛，由 delegate 异步报错 → scheduleReconnect。
    func start() {
        guard !isStarted else { return }
        isStarted = true
        openPort()
    }

    /// 停止监听（app 退出时调）。
    func stop() {
        cancelReconnect()
        port?.close()
        port = nil
        isStarted = false
        status = .disconnected
    }

    private func openPort() {
        guard port == nil else { return }

        guard let p = ORSSerialPort(path: Self.path) else {
            // path 不存在（设备未插）→ ORSSerialPort(path:) 返回 nil。
            // 对齐 Python：不崩，等重连。
            // 注意：这里不能 scheduleReconnect，因为 start() 是用户主动调用一次；
            // 但 openPort 在重连链里也会走，所以重连靠 scheduleReconnect 维护。
            log("串口 \(Self.path) 不可用（设备未插？），\(Int(Self.reconnectDelay)) 秒后重连")
            status = .disconnected
            scheduleReconnect()
            return
        }

        p.delegate = self
        // ★ 关键坑（research note #1/#2）：默认 baudRate=19200（ORSSerialPort.m:183），不设会丢首批数据。
        // 必须在 open() 之前设。Python 跑的就是 115200。
        // ORSSerialPort.baudRate 是 NSNumber（Objective-C 桥接），Int 直接赋值会类型不匹配。
        p.baudRate = NSNumber(value: Self.baudRate)
        p.allowsNonStandardBaudRates = false   // 115200 是标准 baud，无需开
        p.numberOfStopBits = 1
        p.parity = .none
        // 用 descriptor 让 ORSSerialPort 自己缓冲+按包交付，不再手写 didReceiveData 切行。
        p.startListeningForPackets(matching: lineDescriptor)

        status = .connecting
        p.open()    // void；失败走 serialPort(_:didEncounterError:)
        port = p
    }

    /// 安排延迟重连（复刻 Python 的"循环重试"语义，但固定 5 秒避免 spin）。
    private func scheduleReconnect() {
        cancelReconnect()
        let work = DispatchWorkItem { [weak self] in
            self?.openPort()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelay, execute: work)
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    // MARK: - 日志（轻量包装，对齐 Python log() 的 "[HH:MM:SS] msg" 格式）

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        // 对齐 spec/logging-guidelines.md 的 log() 约定（"[HH:MM:SS] msg" + flush）。
        // menu bar app 的 stdout 可能被 buffer，所以走 stderr + 自己 flush。
        let line = "[\(ts)] \(msg)\n"
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }
}

// MARK: - ORSSerialPortDelegate（全部 main queue 回调，全 @objc 方法）
//
// ORSSerialPortDelegate 是 @objc 协议（头文件 @objc 标注），方法必须显式 @objc 才能匹配。
// 全部在 main queue 调用（ORSSerialPort.h:567 注释明确），可直接更新 SwiftUI 状态。

extension SerialMonitor {

    // 端口已成功打开
    @objc func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        log("串口已打开")
        status = .connected
        lastError = nil
    }

    // 按行解析走这里（descriptor 帮你缓冲 + 切包 + 正则匹配）。
    // 原始字节流走 didReceiveData，本场景不需要（避免双重缓冲）。
    @objc func serialPort(_ serialPort: ORSSerialPort,
                          didReceivePacket packetData: Data,
                          matchingDescriptor descriptor: ORSSerialPacketDescriptor) {
        // packetData 形如 "button down k3"；descriptor 已保证匹配 linePattern。
        guard let line = String(data: packetData, encoding: .utf8) else { return }

        // 阶段 F：正则提取抽成纯函数 `parseLine`（见上），这里只调一次，行为不变。
        guard let event = SerialMonitor.parseLine(line) else { return }

        lastEvent = event
        buttonEvents.send(event)
        log("\(event.button) \(event.pressed ? "▼ down" : "▲ up")")
    }

    // @required（ORSSerialPort.h:588）：USB-CDC 设备拔掉 / 断电时回调。
    // 收到后必须立刻置 port=nil，否则 port 实例行为未定义。
    @objc func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        log("⚠️ 串口被移除（设备拔了？），\(Int(Self.reconnectDelay)) 秒后重连")
        port = nil
        status = .disconnected
        scheduleReconnect()
    }

    // open() 失败 / read 出错 / ioctl 出错都走这里（NSPOSIXErrorDomain）。
    // 错误码语义：
    //   EPERM(1)  → entitlement 缺（com.apple.security.device.serial 没加 / sandbox 未签名）
    //   EBUSY(16) → 端口被占（旧版 Python 客户端 vibe_control.py / 其他进程开着）→ 等会儿重试
    //   ENXIO(6)  → 设备已拔，serialPortWasRemovedFromSystem 也会来
    //   ENOENT(2) → 路径不存在
    @objc func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        let nsError = error as NSError
        let msg = "串口错误: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)"
        log("⚠️ \(msg)")
        lastError = msg
        status = .error

        // EBUSY / ENOENT → 等会儿重连。EPERM 是配置错误（entitlement），重连也修不了，
        // 但仍安排重连，避免用户改完 entitlement 后需重启 app（代价是日志会刷，可接受）。
        port?.close()
        port = nil
        scheduleReconnect()
    }

    @objc func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        log("串口已关闭")
        status = .disconnected
    }
}

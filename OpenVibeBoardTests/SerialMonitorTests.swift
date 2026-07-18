//
//  SerialMonitorTests.swift
//  OpenVibeBoardTests
//
//  阶段 F：SerialMonitor.parseLine 纯函数测试。
//
//  parseLine 是阶段 F 从 delegate 抽出的纯函数（正则 capture group 提取）。
//  副作用（端口/重连/ORSSerialPort delegate）由 B 阶段实测门覆盖，不在此测。
//

import Foundation
import Testing
@testable import OpenVibeBoard

@Suite("SerialMonitor.parseLine")
enum ParseLineTests {

    @Test("button down k3 → ButtonEvent(k3, true)")
    static func downK3() throws {
        let event = try #require(SerialMonitor.parseLine("button down k3"))
        #expect(event.button == "k3")
        #expect(event.pressed == true)
    }

    @Test("button up k12 → ButtonEvent(k12, false)，验证 \\d+ 容纳 k10+")
    static func upK12() throws {
        let event = try #require(SerialMonitor.parseLine("button up k12"))
        #expect(event.button == "k12")
        #expect(event.pressed == false)
    }

    @Test("非法输入返回 nil", arguments: [
        "garbage",          // 完全不匹配
        "button down k",    // 缺数字（pattern 要求 \d+）
        "button down",      // 缺按钮名
        "down k3",          // 缺 "button " 前缀
        "",                 // 空串
    ])
    static func invalid(line: String) {
        #expect(SerialMonitor.parseLine(line) == nil)
    }
}

@Suite("SerialMonitor 串口选择")
struct SerialPortSelectionTests {
    @Test("保存路径优先，即使当前不可用")
    func savedPathWins() {
        let path = SerialMonitor.preferredPath(
            savedPath: "/dev/cu.saved-device",
            availablePaths: ["/dev/cu.usbmodem4101"]
        )
        #expect(path == "/dev/cu.saved-device")
    }

    @Test("无保存路径时稳定选择排序后的第一个 usbmodem")
    func discoversUSBModem() {
        let path = SerialMonitor.preferredPath(
            savedPath: nil,
            availablePaths: [
                "/dev/cu.Bluetooth-Incoming-Port",
                "/dev/cu.usbmodem4201",
                "/dev/cu.usbmodem3101",
            ]
        )
        #expect(path == "/dev/cu.usbmodem3101")
    }

    @Test("没有匹配设备时保留历史默认路径")
    func fallsBackToHistoricalPath() {
        let path = SerialMonitor.preferredPath(
            savedPath: nil,
            availablePaths: ["/dev/cu.Bluetooth-Incoming-Port"]
        )
        #expect(path == SerialMonitor.defaultPath)
    }

    @Test("手动选择会更新状态并持久化")
    @MainActor
    func selectionPersists() throws {
        let suiteName = "SerialMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitor = SerialMonitor(defaults: defaults, automaticallyStarts: false)
        monitor.selectPort(path: "/dev/cu.test-device")

        #expect(monitor.configuredPath == "/dev/cu.test-device")
        #expect(defaults.string(forKey: "serialPortPath") == "/dev/cu.test-device")
        #expect(monitor.status == SerialMonitor.Status.disconnected)
    }
}

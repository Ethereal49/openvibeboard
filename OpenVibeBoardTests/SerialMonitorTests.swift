//
//  SerialMonitorTests.swift
//  OpenVibeBoardTests
//
//  阶段 F：SerialMonitor.parseLine 纯函数测试。
//
//  parseLine 是阶段 F 从 delegate 抽出的纯函数（正则 capture group 提取）。
//  副作用（端口/重连/ORSSerialPort delegate）由 B 阶段实测门覆盖，不在此测。
//

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

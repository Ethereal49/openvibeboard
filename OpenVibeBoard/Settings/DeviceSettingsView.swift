//
//  DeviceSettingsView.swift
//  OpenVibeBoard
//
//  串口设备选择与连接状态。选择后由 SerialMonitor 立即切换并持久化。
//

import SwiftUI

struct DeviceSettingsView: View {
    @EnvironmentObject private var serial: SerialMonitor

    private var choices: [String] {
        Array(Set(serial.availablePaths + [serial.configuredPath])).sorted()
    }

    var body: some View {
        Form {
            Section("串口连接") {
                LabeledContent("状态") {
                    Label(serial.status.rawValue, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                }

                Picker("串口", selection: Binding(
                    get: { serial.configuredPath },
                    set: { serial.selectPort(path: $0) }
                )) {
                    ForEach(choices, id: \.self) { path in
                        Text(choiceLabel(for: path))
                            .tag(path)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("波特率", value: String(SerialMonitor.baudRate))

                if !serial.isConfiguredPortAvailable {
                    Label("所选串口当前不可用", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if let error = serial.lastError, serial.status == .error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var statusSymbol: String {
        switch serial.status {
        case .connected:
            "checkmark.circle.fill"
        case .connecting:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .disconnected:
            "circle.dashed"
        case .error:
            "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch serial.status {
        case .connected:
            .green
        case .connecting, .disconnected:
            .secondary
        case .error:
            .red
        }
    }

    private func choiceLabel(for path: String) -> String {
        serial.availablePaths.contains(path) ? path : "\(path)（不可用）"
    }
}

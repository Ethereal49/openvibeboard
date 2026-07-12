//
//  KeyRecorderView.swift
//  OpenVibeBoard
//
//  SwiftUI 展示 keycap，AppKit 只负责第一响应者和键盘事件采集。
//

import AppKit
import SwiftUI

struct KeyRecorderView: View {
    @Binding var value: String
    @State private var isRecording = false

    private var keycaps: [String] {
        guard let parsed = KeyInjector.parseKey(value) else { return [] }
        return KeyInjector.label(for: parsed.virtualKey, modifiers: parsed.modifiers).map(String.init)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                if keycaps.isEmpty {
                    Text(isRecording ? "请按下组合键" : "点击后录制按键")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, keycap in
                        Text(keycap)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .frame(minWidth: 28, minHeight: 26)
                            .padding(.horizontal, keycap == "␣" ? 10 : 0)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(.separator, lineWidth: 1)
                            }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                    .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 2 : 1)
            }

            KeyEventCapture(value: $value, isRecording: $isRecording)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .help("点击后按下要执行的按键或组合键")
    }
}

private struct KeyEventCapture: NSViewRepresentable {
    @Binding var value: String
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onRecordingChange = { isRecording = $0 }
        view.onCapture = { value = $0 }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onRecordingChange = { isRecording = $0 }
        nsView.onCapture = { value = $0 }
    }
}

private final class KeyCaptureNSView: NSView {
    var onCapture: ((String) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        onRecordingChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        onRecordingChange?(false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = Self.cgModifiers(from: event.modifierFlags)
        guard let descriptor = KeyInjector.descriptor(
            for: CGKeyCode(event.keyCode),
            modifiers: modifiers
        ) else {
            NSSound.beep()
            return
        }
        onCapture?(descriptor)
    }

    private static func cgModifiers(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        return result
    }
}

//
//  Accessibility.swift
//  OpenVibeBoard
//
//  阶段 C：Accessibility TCC 权限检查/请求（CGEvent 注入的唯一前置）。
//
//  对齐 Python spec quality-guidelines.md 的"权限缺失 = 警告，非崩溃"语义：
//    - 首次启动弹一次系统授权对话框
//    - 运行时每次按键前快速检查；未授权时 log + 菜单栏图标提示，不崩不重复弹窗
//
//  关键 API：
//    - AXIsProcessTrusted()：只查询，不弹窗（运行时检查用，纳秒级开销）
//    - AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])：弹系统对话框
//
//  ⚠ kAXTrustedCheckOptionPrompt 是 Unmanaged<CFBoolean>，必须 .takeRetainedValue()
//  才能用，否则运行时 crash（每个 Swift AX 项目的标准写法）。
//

import ApplicationServices
import AppKit
import Foundation

/// Accessibility 权限检查/请求。所有方法静态调用，无状态。
enum Accessibility {

    /// 检查 + 按需弹一次系统对话框。
    ///
    /// @return true 已授权；false 未授权（已弹窗提示用户去系统设置）。
    ///
    /// 调用时机：app 启动后 menu bar 图标已显示，但用户**第一次**按物理键之前。
    /// 不阻塞 UI（系统对话框异步弹）。
    @discardableResult
    static func ensure() -> Bool {
        if AXIsProcessTrusted() { return true }

        // kAXTrustedCheckOptionPrompt.takeRetainedValue() 不能漏，否则 crash。
        // options = { kAXTrustedCheckOptionPrompt: true } → 系统弹「打开系统设置」对话框。
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        return false
    }

    /// 用户主动点击时，明确打开 System Settings → Privacy & Security → Accessibility。
    /// `ensure()` 的系统 prompt 只保证首次请求，不保证被拒绝后再次打开设置页。
    @MainActor
    static func openSystemSettings() {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ), let paneURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            _ = ensure()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { application, error in
            guard error == nil else {
                _ = ensure()
                return
            }

            DispatchQueue.main.async {
                NSWorkspace.shared.open(paneURL)
                application?.activate(options: [.activateAllWindows])
            }
        }
    }

    /// 运行时快速检查（每次按键前调，纳秒级开销）。
    /// 不弹窗。对应 Python `HAS_CGEVENT` flag 的运行时检查语义。
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}

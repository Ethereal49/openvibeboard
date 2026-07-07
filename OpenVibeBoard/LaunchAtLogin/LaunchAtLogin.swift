//
//  LaunchAtLogin.swift
//  OpenVibeBoard
//
//  阶段 E：SMAppService 应用内自启（macOS 13+，deployment 14 满足）。
//
//  对齐 prd.md R2：用 SMAppService.mainApp 注册为「登录项」，替代 Python 时代的
//  launchd plist / 外部脚本。用户在「系统设置 → 通用 → 登录项与扩展」里看到 OpenVibeBoard，
//  可系统级开关，比手动维护 plist 干净（Apple 自 macOS 13 起主推这套）。
//
//  关键 API（ServiceManagement.framework）：
//    - SMAppService.mainApp：当前 app 的 login item service 单例（不是 SMAppService.loginItem(identifier:)，
//      那条是给 helper tool / bundle 内子 target 用的，主 app 用 mainApp）
//    - register() throws / unregister() throws：注册/取消注册登录项
//    - status: SMAppService.Status → .enabled / .notRegistered / .notFound / .requiresApproval（4 个成员，无 notAvailable）
//
//  坑（实现核对）：
//    1. register() 即使成功也未必 .enabled：首次注册 status 可能停在 .requiresApproval，
//       系统会引导用户去「登录项」面板确认（macOS 13/14 行为）。我们只负责 register，不强求 .enabled。
//    2. status 必须「每次重读」，不能缓存：用户随时能在系统设置里改，缓存会显示陈旧勾选态。
//    3. throws 不能静默吞：register/unregister 失败（少见，bundle 损坏 / sandbox 配置错）要 log，
//       否则菜单勾选态与系统状态对不上、且无声失败 → 违反规则 12「大声失败」。
//    4. 不需要任何 entitlement：SMAppService 不像串口/Accessibility 要 TCC 授权，主 app 直接 register。
//
//  封装形态：enum + 静态方法，无状态。对齐 Permissions/Accessibility.swift 的「能力封装」风格。
//

import Foundation
import ServiceManagement

/// 应用内自启（登录项）注册/查询。所有方法静态调用，无状态。
enum LaunchAtLogin {

    /// 当前是否已注册为登录项。
    ///
    /// 直接读 SMAppService.mainApp.status，**每次调用都重新查**（不缓存）：
    /// 用户可能在「系统设置 → 登录项」里手动改过，缓存会显示陈旧勾选态。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册为登录项。失败打 log（不静默吞），调用方据返回值刷新 UI。
    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            log("已注册开机自启（status: \(statusLabel(SMAppService.mainApp.status))）")
            return SMAppService.mainApp.status == .enabled
        } catch {
            // 失败场景极少（bundle 损坏 / sandbox 配置错 / 多次重复 register 不会 throw，会留在原 status）。
            // 强调「大声失败」：log 错误，UI 勾选态会因 isEnabled=false 自动反映未注册。
            log("⚠️ 注册开机自启失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 取消登录项注册。失败打 log。
    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            log("已取消开机自启")
            return true
        } catch {
            log("⚠️ 取消开机自启失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 切换勾选态（菜单 Toggle 的 action 调这个）。
    /// 返回切换后的 isEnabled，供 UI 刷新。
    @discardableResult
    static func toggle() -> Bool {
        if isEnabled {
            _ = disable()
        } else {
            _ = enable()
        }
        // 重新查 status 作为权威值（register 可能落到 .requiresApproval，需如实返回 false）。
        return isEnabled
    }

    // MARK: - 日志（轻量包装，对齐 SerialMonitor.log 的 "[HH:MM:SS] msg" 格式）

    private static func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }

    /// status 枚举转中文标签（log 用，避免 rawValue 英文混入）。
    private static func statusLabel(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:            return "已启用"
        case .notRegistered:      return "未注册"
        case .notFound:           return "未找到"
        case .requiresApproval:   return "待批准"
        @unknown default:         return "未知"
        }
    }
}

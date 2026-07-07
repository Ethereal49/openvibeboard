# SMAppService — 应用内开机自启（阶段 E）

> 来源：Apple Service Management 官方文档（context7 `/websites/developer_apple_servicemanagement`，2026-07-06）
> macOS 13+；当前 deployment target 14 ✓

## 核心 API

`SMAppService`（ServiceManagement.framework）管理 app 作为 login item。主 app 自启用 `mainApp`：

```swift
class var mainApp: SMAppService { get }        // macOS 13+
func register() throws                          // 注册（开机启动）
func unregister() throws                        // 注销（throws 版）
func unregister(completionHandler: ((Error?) -> Void)?)
var status: SMAppService.Status { get }         // 只读，查当前状态
```

## Status 枚举

```swift
enum Status {
    case enabled          // 已注册且可运行 ← 判断「已启用」用这个
    case notRegistered    // 未注册
    case requiresApproval // 已注册，但需用户在「系统设置 > 通用 > 登录项与扩展」手动批准
    case notFound         // 找不到该 service
}
```

判定「自启已开启」：`status == .enabled`。

## 关键坑

1. **status 只读**：不能直接赋值。toggle 走 `register()` / `unregister()`。
2. **register 是 throws**：`try service.register()`，必须 catch，别静默吞错（用 print 或项目现有日志方式记录）。
3. **`.requiresApproval`**：macOS 13+ login items 有系统级开关，用户可能在系统设置里关掉。菜单勾选应把 `.requiresApproval` / `.notRegistered` / `.notFound` 都视为「未真正启用」，只有 `.enabled` 才勾。
4. **状态会外部变化**：用户可在「系统设置 > 通用 > 登录项」手动开关本 app。**菜单每次打开都重读 status，不要缓存**。
5. **mainApp vs loginItem(identifier:)**：本 app 是主 app 自启，用 `SMAppService.mainApp`，**不要**用 `loginItem(identifier:)`（那个需要 helper bundle 在 `Contents/Library/LoginItems/` 目录）。本 app 已是签名 .app，mainApp 路径最简。
6. **无需 entitlement**：`SMAppService.mainApp` 不需要额外 entitlement，比旧 `osascript` / launchd plist 简单。

## 推荐封装（伪代码，需匹配项目风格）

```swift
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            print("SMAppService register failed: \(error)")
            return false
        }
    }

    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            print("SMAppService unregister failed: \(error)")
            return false
        }
    }

    static func toggle() {
        if isEnabled { disable() } else { enable() }
    }
}
```

菜单接入：Toggle「开机自启」，`isOn: LaunchAtLogin.isEnabled`，action = `LaunchAtLogin.toggle()`。菜单 willOpen / 重建时重读 status。

## 验证

勾选 Toggle → 注销重登 → app 自动启动 → 取消勾选 → 注销重登 → 不启动。
（`.requiresApproval` 场景：首次可能需在系统设置批准，README 阶段 G 文档化。）

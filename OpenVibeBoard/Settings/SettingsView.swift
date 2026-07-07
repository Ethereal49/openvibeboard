//
//  SettingsView.swift
//  OpenVibeBoard
//
//  阶段 D：SwiftUI Settings 配置面板（替代 Python v0.1 的 index.html + HTTP server）。
//
//  Settings scene 根视图：TabView 容器，两个 tab：
//    - 按键（KeyMappingsView）：配置编辑，本地 @State 副本 + 显式「保存」+ 热生效
//    - 关于（AboutView）：app 名 / 版本 / 一句话说明
//
//  D 阶段增强（保留编辑语义、Binding 工厂、load/save 不动，仅 UI 重做 + 加预览/重置）：
//    - TabView 两 tab，@AppStorage 记住上次 tab（Apple 范式）
//    - Section header 加 type 语义（k1 · 命令 / k1 · 文本 / k1 · 按键）
//    - value 实时预览（调 KeyInjector.label(...) 反向渲染符号）
//    - 「重置默认配置」二次确认
//
//  macOS 15+ API（deployment 15）：Tab(_:systemImage:value:) / @AppStorage；NSApp.activate 在 MenuBarView（macOS 14+）。
//

import SwiftUI

/// Settings 场景根视图：TabView 容器。
struct SettingsView: View {

    /// 上次选中的 tab，跨 App 启动记住（Apple 范式：系统偏好设置也这样）。
    /// @AppStorage 对 RawRepresentable（String raw）直接支持，无需手动 Binding 包装——
    /// 实测手动 String↔Enum Binding 包装在 macOS 15 Tab API 下 selection 不可靠（点部分 tab 不切）。
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .keys

    var body: some View {
        // macOS 15+ Tab(_:systemImage:value:) API（deployment 已提至 15）。
        TabView(selection: $selectedTab) {
            Tab("按键", systemImage: "keyboard", value: SettingsTab.keys) {
                KeyMappingsView()
            }
            Tab("关于", systemImage: "info.circle", value: SettingsTab.about) {
                AboutView()
            }
        }
        // minWidth/minHeight 给 Form 编辑区留够空间，避免长字符段挤压。
        .frame(minWidth: 520, minHeight: 400)
    }
}

/// Tab 标识。rawValue 持久化到 @AppStorage，必须稳定（不要随意改字符串）。
enum SettingsTab: String {
    case keys
    case about
}

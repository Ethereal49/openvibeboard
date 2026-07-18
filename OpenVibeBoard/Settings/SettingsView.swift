//
//  SettingsView.swift
//  OpenVibeBoard
//
//  SwiftUI Settings 配置面板。设备设置与按键映射使用系统标准 tab 导航。
//

import SwiftUI

/// Settings 场景根视图。关于信息由菜单栏的标准 About Panel 提供。
struct SettingsView: View {
    var body: some View {
        TabView {
            DeviceSettingsView()
                .tabItem {
                    Label("设备", systemImage: "cable.connector")
                }

            KeyMappingsView()
                .tabItem {
                    Label("按键映射", systemImage: "keyboard")
                }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

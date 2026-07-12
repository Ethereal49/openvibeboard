//
//  SettingsView.swift
//  OpenVibeBoard
//
//  SwiftUI Settings 配置面板。关于信息使用系统标准 About Panel，设置窗口只保留映射工作流。
//

import SwiftUI

/// Settings 场景根视图。关于信息由菜单栏的标准 About Panel 提供，设置窗口只保留配置工作流。
struct SettingsView: View {
    var body: some View {
        KeyMappingsView()
            .frame(minWidth: 760, minHeight: 520)
    }
}

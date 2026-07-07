//
//  AboutView.swift
//  OpenVibeBoard
//
//  Settings 「关于」tab：app 名 / 版本 / 一句话说明。
//
//  对齐 macOS 关于面板的极简风格——大标题 + 版本 + 一句话，不堆砌 feature 列表。
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("OpenVibeBoard")
                .font(.title)
                .fontWeight(.semibold)

            if let version = appVersion {
                Text("版本 \(version)")
                    .foregroundStyle(.secondary)
            }

            Text("为 ESP32-S3 键盘做 PC 端接管")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 从 Bundle 读 CFBundleShortVersionString（如 "0.2.0"）。
    /// 读失败（极端：infoDictionary 缺字段）返回 nil，UI 隐藏版本行而非显示占位。
    private var appVersion: String? {
        guard let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !v.isEmpty else {
            return nil
        }
        return v
    }
}

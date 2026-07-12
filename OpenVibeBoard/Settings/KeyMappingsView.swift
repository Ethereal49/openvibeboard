//
//  KeyMappingsView.swift
//  OpenVibeBoard
//
//  Settings 主界面：左侧映射列表，右侧编辑当前映射，底部固定保存状态。
//

import SwiftUI

struct KeyMappingsView: View {
    @State private var config: Config = [:]
    @State private var savedConfig: Config = [:]
    @State private var selectedKey: String?
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var savedFlash: String?
    @State private var showResetConfirm = false

    private var sortedKeys: [String] {
        config.keys.sorted()
    }

    private var nextKey: String? {
        for index in 1...999 where config["k\(index)"] == nil {
            return "k\(index)"
        }
        return nil
    }

    private var isDirty: Bool {
        didLoad && config != savedConfig
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .confirmationDialog(
            "确定重置为默认配置？当前所有改动会被替换。",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("重置为默认", role: .destructive) {
                config = defaultConfig
                selectedKey = sortedKeys.first
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            await load()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedKey) {
            ForEach(sortedKeys, id: \.self) { key in
                MappingSidebarRow(key: key, mapping: config[key])
                    .tag(key)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("按键映射")
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button(action: addKey) {
                    Image(systemName: "plus")
                }
                .help("添加按键映射")
                .disabled(nextKey == nil)

                Button(role: .destructive, action: deleteSelectedKey) {
                    Image(systemName: "minus")
                }
                .help("删除所选映射")
                .disabled(selectedKey == nil)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !didLoad {
            ProgressView("加载配置中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let key = selectedKey, config[key] != nil {
            KeyMappingEditorView(key: key, mapping: mappingBinding(for: key))
                .safeAreaInset(edge: .bottom) {
                    saveBar
                }
        } else {
            ContentUnavailableView(
                "选择一个按键映射",
                systemImage: "keyboard",
                description: Text("从左侧选择映射，或添加一个新的映射。")
            )
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
        }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button("重置默认…", role: .destructive) {
                showResetConfirm = true
            }

            Spacer()

            if let savedFlash {
                Label(savedFlash, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else if isDirty {
                Text("有未保存的更改")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("保存") {
                Task { await save() }
            }
            .keyboardShortcut("s")
            .buttonStyle(.borderedProminent)
            .disabled(!isDirty || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func mappingBinding(for key: String) -> Binding<KeyConfig> {
        Binding(
            get: { config[key] ?? KeyConfig(type: "cmd", value: "") },
            set: { config[key] = $0 }
        )
    }

    private func load() async {
        if config.isEmpty {
            _ = await ConfigStore.shared.load()
        }
        let snapshot = await ConfigStore.shared.snapshot()
        config = snapshot
        savedConfig = snapshot
        selectedKey = snapshot.keys.sorted().first
        didLoad = true
    }

    private func save() async {
        guard isDirty, !isSaving else { return }
        isSaving = true
        await ConfigStore.shared.save(config)
        savedConfig = config
        savedFlash = "已保存并生效"
        KeyMappingsView.log("配置已保存并热生效")
        try? await Task.sleep(for: .seconds(1.5))
        savedFlash = nil
        isSaving = false
    }

    private func addKey() {
        guard let key = nextKey else { return }
        config[key] = KeyConfig(type: "cmd", value: "", desc: nil)
        selectedKey = key
    }

    private func deleteSelectedKey() {
        guard let key = selectedKey else { return }
        config.removeValue(forKey: key)
        selectedKey = sortedKeys.first
    }

    nonisolated private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[OpenVibeBoard] \(message)\n".utf8))
    }
}

private struct MappingSidebarRow: View {
    let key: String
    let mapping: KeyConfig?

    private var summary: String {
        guard let mapping else { return "未配置" }
        switch mapping.type {
        case "key":
            guard let parsed = KeyInjector.parseKey(mapping.value) else { return "无效按键" }
            return KeyInjector.label(for: parsed.virtualKey, modifiers: parsed.modifiers)
        case "text":
            return mapping.value.isEmpty ? "空文本" : mapping.value
        case "cmd":
            return mapping.value.isEmpty ? "空命令" : mapping.value
        default:
            return "未知类型"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .fontWeight(.medium)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch mapping?.type {
        case "key": return "keyboard"
        case "text": return "text.cursor"
        default: return "terminal"
        }
    }
}

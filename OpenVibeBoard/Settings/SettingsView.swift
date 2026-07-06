//
//  SettingsView.swift
//  OpenVibeBoard
//
//  阶段 D：SwiftUI Settings 配置面板（替代 Python v0.1 的 index.html + HTTP server）。
//
//  编辑本地 @State 副本，显式「保存」按钮调 ConfigStore.save() 写盘 + 更新内存。
//  热生效天然成立：ActionDispatcher 每次按键 await ConfigStore.shared.snapshot()[button]
//  读最新快照，保存后下一次物理按键自动读到新配置，不需要额外通知管道。
//
//  不做每键击键即时写盘（半编辑状态写盘无意义且高频 IO），对齐 Python v0.1 的
//  「点保存才落盘」语义（vibe_control.py 的 do_PUT / 配置已更新并热生效）。
//
//  macOS 13 限定：不使用 macOS 14+ 的 SettingsLink / EnvironmentValues.openSettings。
//

import SwiftUI

/// Settings 场景根视图。Form 列出所有按键映射，每个 key 一个 Section。
///
/// 列顺序：key 名升序（k1, k2, ...），保证用户看到的顺序稳定（dict 本身无序）。
struct SettingsView: View {

    /// 本地可变配置副本。
    ///
    /// 出现时（.task）从 ConfigStore.shared.snapshot() 异步加载。
    /// 编辑期间所有改动只动这个 @State，不触碰 actor；
    /// 点「保存」才 await ConfigStore.shared.save(local)。
    @State private var config: Config = [:]

    /// 是否正在保存（防双击 + 轻量确认视觉）。保存完成后短暂保持 true 给用户反馈。
    @State private var isSaving = false

    /// 是否已加载完成。加载前显示占位，避免空 Form 闪一下又填充。
    @State private var didLoad = false

    var body: some View {
        Form {
            if !didLoad {
                Section {
                    Text("加载配置中…")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(sortedKeys, id: \.self) { key in
                    keySection(for: key)
                }

                Section {
                    Button("添加按键") { addKey() }
                        .disabled(nextKey == nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task { await save() }
                }
                .disabled(!didLoad || isSaving)
            }
        }
        .task {
            await load()
        }
    }

    // MARK: - 排序后的 key 列表

    /// dict 无序，UI 需稳定顺序。按 key 名升序排（"k1" < "k2" < ...）。
    /// k10+ 也能正确排序（ZeroPad 不做，靠 String 自然比较 + k 前缀一致；
    /// 实际 key 数量不会到 10 个，String 字典序在此范围够用）。
    private var sortedKeys: [String] {
        config.keys.sorted()
    }

    /// 下一个可用的 kN 键名（k1, k2, ... 递增到第一个未占用的）。
    /// 找不到（极端：k1...kN 全占）返回 nil，按钮置灰。
    private var nextKey: String? {
        var i = 1
        while true {
            let candidate = "k\(i)"
            if config[candidate] == nil { return candidate }
            i += 1
            // 防御：极端情况下不无限循环（实际键数 < 100）。
            if i > 999 { return nil }
        }
    }

    // MARK: - 单个 key 的 Section

    @ViewBuilder
    private func keySection(for key: String) -> some View {
        Section {
            // type：决定下方条件字段。改 type 时重置无关字段，避免脏数据落盘
            // （如 type 从 key 切到 cmd，mode 字段对 cmd 无意义，清掉）。
            Picker("类型", selection: typeBinding(for: key)) {
                Text("命令 (cmd)").tag("cmd")
                Text("按键 (key)").tag("key")
                Text("文本 (text)").tag("text")
            }
            .pickerStyle(.segmented)

            TextField("value", text: valueBinding(for: key), prompt: Text(valuePrompt(for: key)))

            TextField("描述（可选）", text: descBinding(for: key))

            // 条件字段：仅 key 类型显示 mode（tap/hold）
            if config[key]?.type == "key" {
                Picker("mode", selection: modeBinding(for: key)) {
                    Text("tap（瞬时）").tag("tap")
                    Text("hold（按住）").tag("hold")
                }
                .pickerStyle(.segmented)
            }

            // 条件字段：仅 text 类型显示 enter（粘贴后是否回车）
            if config[key]?.type == "text" {
                Toggle("粘贴后回车", isOn: enterBinding(for: key))
            }

            Button("删除 \(key)", role: .destructive) {
                config.removeValue(forKey: key)
            }
        } header: {
            Text(key)
        }
    }

    // MARK: - Binding 工厂

    /// 所有字段经 Binding 直读直写 config[key]，避免 SwiftUI TextField 强制解包 Optional。
    /// config[key] 为 nil 时（不应发生，section 只在 key 存在时渲染）返回空串默认值。

    private func typeBinding(for key: String) -> Binding<String> {
        Binding(
            get: { config[key]?.type ?? "cmd" },
            set: { newType in
                if var cfg = config[key] {
                    cfg.type = newType
                    config[key] = cfg
                }
                resetConditionalFields(for: key, type: newType)
            }
        )
    }

    private func valueBinding(for key: String) -> Binding<String> {
        Binding(
            get: { config[key]?.value ?? "" },
            set: { newValue in
                guard var cfg = config[key] else { return }
                cfg.value = newValue
                config[key] = cfg
            }
        )
    }

    private func descBinding(for key: String) -> Binding<String> {
        Binding(
            get: { config[key]?.desc ?? "" },
            set: { newValue in
                guard var cfg = config[key] else { return }
                cfg.desc = newValue.isEmpty ? nil : newValue
                config[key] = cfg
            }
        )
    }

    private func modeBinding(for key: String) -> Binding<String> {
        Binding(
            get: { config[key]?.mode ?? "tap" },
            set: { newValue in
                guard var cfg = config[key] else { return }
                cfg.mode = newValue
                config[key] = cfg
            }
        )
    }

    private func enterBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { config[key]?.enter ?? true },
            set: { newValue in
                guard var cfg = config[key] else { return }
                cfg.enter = newValue
                config[key] = cfg
            }
        )
    }

    /// 改 type 时重置无关字段，避免脏数据落盘：
    ///   - cmd：清 mode（cmd 无 mode）、清 enter（cmd 无 enter）
    ///   - key：清 enter（key 无 enter）；mode 默认 tap（若为空）
    ///   - text：清 mode（text 无 mode）；enter 默认 true（若为空）
    private func resetConditionalFields(for key: String, type: String) {
        guard var cfg = config[key] else { return }
        switch type {
        case "cmd":
            cfg.mode = nil
            cfg.enter = nil
        case "key":
            cfg.enter = nil
            if cfg.mode == nil { cfg.mode = "tap" }
        case "text":
            cfg.mode = nil
            if cfg.enter == nil { cfg.enter = true }
        default:
            break
        }
        config[key] = cfg
    }

    /// value 字段的 placeholder 提示，按 type 给不同示例，降低填写门槛。
    private func valuePrompt(for key: String) -> String {
        switch config[key]?.type {
        case "cmd":  return "如 open -a Codex"
        case "key":  return "如 ctrl+c / option+d / esc"
        case "text": return "如 继续"
        default:     return ""
        }
    }

    // MARK: - 加载 / 保存

    /// 出现时从 ConfigStore 读快照。ConfigStore 是 actor，必须 await。
    /// 同时兜底：若 actor 还没 load()（极端启动竞态），snapshot() 返回空 dict，
    /// 此时调一次 load() 保证用户看到默认配置而非空白。
    private func load() async {
        if config.isEmpty {
            // actor 未 load 时 snapshot() 返回空；主动触发 load 写默认。
            // 已 load 时 load() 是幂等 no-op。
            _ = await ConfigStore.shared.load()
        }
        config = await ConfigStore.shared.snapshot()
        didLoad = true
    }

    /// 保存本地副本到 ConfigStore（原子写盘 + 内存更新）。
    /// 下一次物理按键 ActionDispatcher.snapshot() 自动读到新配置 → 热生效。
    /// 轻量确认：isSaving 短暂置 true（按钮灰 0.6s），不弹窗。
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        await ConfigStore.shared.save(config)
        SettingsView.log("配置已保存并热生效")
        // 给用户一个可见的「已保存」反馈窗口（防闪）。
        try? await Task.sleep(nanoseconds: 600_000_000)
        isSaving = false
    }

    // MARK: - 添加按键

    /// 生成下一个 kN 键名并补一个空 KeyConfig，用户立刻能在 Section 里编辑。
    private func addKey() {
        guard let newKey = nextKey else { return }
        config[newKey] = KeyConfig(type: "cmd", value: "", desc: nil)
    }

    // MARK: - 日志（复刻 ActionDispatcher / SerialMonitor 的 stderr + [HH:MM:SS] 格式）

    private static func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }
}

//
//  KeyMappingsView.swift
//  OpenVibeBoard
//
//  Settings 「按键」tab：Form 列出所有按键映射，每个 key 一个 Section。
//
//  从 SettingsView.swift（D 阶段原实现）搬迁而来，保留所有编辑语义：
//    - 本地 @State config 副本
//    - 显式「保存」按钮（防半编辑状态写盘）
//    - 热生效（ActionDispatcher 每次按键 await snapshot() 读最新）
//    - Binding 工厂 / resetConditionalFields / load / save / addKey 全保留
//
//  D 阶段增强（仅 UI 层）：
//    1. Section header 加 type 语义后缀（k1 · 命令 / k1 · 文本 / k1 · 按键）
//    2. type/mode Picker 改 .menu（省空间，segmented 在多 Section 里拥挤）
//    3. value TextField 下方实时预览（调 KeyInjector.label(...) 反向渲染）
//    4. 「重置默认配置」二次确认
//

import SwiftUI

struct KeyMappingsView: View {

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

    /// 保存成功的可见反馈文字。短暂显示后清空（对齐 isSaving 的 0.6s 节奏）。
    @State private var savedFlash: String? = nil

    /// 「重置默认」确认对话框触发。
    @State private var showResetConfirm = false

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

                // 保存/重置放 Form 内底部（不放窗口 .toolbar）：
                // macOS 15 Settings + TabView 子视图的 .toolbar 与窗口 tab bar 冲突，实测按钮不渲染。
                // Form 内 Section 按钮确定可见。HStack：左重置（destructive），右保存 + 已保存反馈。
                Section {
                    HStack {
                        Button("重置默认…", role: .destructive) {
                            showResetConfirm = true
                        }
                        .disabled(!didLoad)
                        Spacer()
                        if let flash = savedFlash {
                            Text(flash)
                                .font(.caption)
                                .foregroundStyle(Color.green)
                        }
                        Button("保存") {
                            Task { await save() }
                        }
                        .disabled(!didLoad || isSaving)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "确定重置为默认配置？当前所有改动会丢失。",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("重置为默认", role: .destructive) {
                resetToDefault()
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            await load()
        }
    }

    // MARK: - 排序后的 key 列表

    /// dict 无序，UI 需稳定顺序。按 key 名升序排（"k1" < "k2" < ...）。
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
            if i > 999 { return nil }
        }
    }

    // MARK: - 单个 key 的 Section

    @ViewBuilder
    private func keySection(for key: String) -> some View {
        Section {
            // type：决定下方条件字段。改 type 时重置无关字段，避免脏数据落盘。
            Picker("类型", selection: typeBinding(for: key)) {
                Text("命令 (cmd)").tag("cmd")
                Text("按键 (key)").tag("key")
                Text("文本 (text)").tag("text")
            }
            // .menu 比 .segmented 省空间——多 Section 拥挤时 segmented 会撑宽。
            .pickerStyle(.menu)

            TextField("value", text: valueBinding(for: key), prompt: Text(valuePrompt(for: key)))

            // value 实时预览（核心增强）：key 显示 modifier+符号，cmd 显示命令首词，
            // text 显示字符数 + enter 标记。失败 nil 红色提示。
            if let preview = valuePreview(for: key) {
                Text(preview.text)
                    .font(.caption)
                    // 三元两边类型必须一致：用 Color.green/.red，避免 .secondary（HierarchicalShapeStyle）
                    // 与 .red（Color）混用编译错误。
                    .foregroundStyle(preview.ok ? Color.secondary : Color.red)
            }

            TextField("描述（可选）", text: descBinding(for: key))

            // 条件字段：仅 key 类型显示 mode（tap/hold）
            if config[key]?.type == "key" {
                Picker("mode", selection: modeBinding(for: key)) {
                    Text("tap（瞬时）").tag("tap")
                    Text("hold（按住）").tag("hold")
                }
                .pickerStyle(.menu)
            }

            // 条件字段：仅 text 类型显示 enter（粘贴后是否回车）
            if config[key]?.type == "text" {
                Toggle("粘贴后回车", isOn: enterBinding(for: key))
            }

            Button("删除 \(key)", role: .destructive) {
                config.removeValue(forKey: key)
            }
        } header: {
            // 语义 header：k1 · 命令 / k1 · 文本 / k1 · 按键
            // 让用户一眼看到每键在做什么，不用展开 section 翻 type。
            Text(sectionHeader(for: key))
        }
    }

    /// Section header 文案：key 名 + type 中文后缀。
    private func sectionHeader(for key: String) -> String {
        let typeLabel: String
        switch config[key]?.type {
        case "cmd":  typeLabel = "命令"
        case "key":  typeLabel = "按键"
        case "text": typeLabel = "文本"
        default:     typeLabel = "—"
        }
        return "\(key) · \(typeLabel)"
    }

    // MARK: - value 实时预览

    /// 预览结果（text + ok 标志：ok=false 时红色显示）。
    private struct PreviewResult {
        let text: String
        let ok: Bool
    }

    /// 按 type 渲染 value 预览：
    ///   - key：调 KeyInjector.parseKey → label 反向渲染（成功）/ 红色「⚠️ 无法解析」（失败）
    ///   - cmd：显示命令字符串原样（首词或整句）
    ///   - text：显示字符数 + enter 标记
    ///   - 空 value：返回 nil（不显示预览，避免空 placeholder 干扰）
    private func valuePreview(for key: String) -> PreviewResult? {
        guard let cfg = config[key] else { return nil }
        let value = cfg.value.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return nil }

        switch cfg.type {
        case "key":
            // parseKey → label 反向渲染。失败（nil）红色提示。
            if let (vk, mods) = KeyInjector.parseKey(value) {
                let symbol = KeyInjector.label(for: vk, modifiers: mods)
                return PreviewResult(text: "预览：\(symbol)", ok: true)
            } else {
                return PreviewResult(text: "⚠️ 无法解析", ok: false)
            }
        case "cmd":
            // 命令：原样显示（用户写啥看到啥，首词或整句都行——首词太短可能误导，
            // 如 "open -a Codex" 取首词只看到 "open"，不如整句直观）。
            return PreviewResult(text: "命令：\(value)", ok: true)
        case "text":
            // 文本：字符数 + enter 标记。中文一个字也算 1 字符（Swift String.count 是字符数）。
            let count = value.count
            let enterMark = (cfg.enter ?? true) ? "  ↩粘贴后回车" : ""
            return PreviewResult(text: "\(count) 字符\(enterMark)", ok: true)
        default:
            return nil
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
            _ = await ConfigStore.shared.load()
        }
        config = await ConfigStore.shared.snapshot()
        didLoad = true
    }

    /// 保存本地副本到 ConfigStore（原子写盘 + 内存更新）。
    /// 下一次物理按键 ActionDispatcher.snapshot() 自动读到新配置 → 热生效。
    /// 轻量确认：isSaving 短暂置 true（按钮灰 0.6s）+ savedFlash 显示「✓ 已保存」。
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        await ConfigStore.shared.save(config)
        KeyMappingsView.log("配置已保存并热生效")
        savedFlash = "✓ 已保存"
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        savedFlash = nil
        isSaving = false
    }

    // MARK: - 添加按键

    /// 生成下一个 kN 键名并补一个空 KeyConfig，用户立刻能在 Section 里编辑。
    private func addKey() {
        guard let newKey = nextKey else { return }
        config[newKey] = KeyConfig(type: "cmd", value: "", desc: nil)
    }

    // MARK: - 重置默认

    /// 重置：选「本地副本待保存」而非「直接落盘」。
    ///
    /// 理由：用户可能点开「重置」后又想反悔，本地副本待保存给一次「检视后取消」的机会；
    /// 直接 save() 是不可逆的，与编辑语义（半编辑状态不写盘）不一致——既然普通编辑要显式保存，
    /// 重置这个「大改动」更应该走同样的路径。用户检视后点「保存」才真正落盘。
    ///
    /// 注意：若用户加载时 actor 已有改动（如外部进程改了 config.json），重置会把那些改动
    /// 在本地副本里抹掉——但本 app 是唯一写入方（无外部进程改 config），不存在此风险。
    private func resetToDefault() {
        config = defaultConfig
    }

    // MARK: - 日志（复刻 ActionDispatcher / SerialMonitor 的 stderr + [HH:MM:SS] 格式）

    private static func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }
}

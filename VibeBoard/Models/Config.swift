//
//  Config.swift
//  VibeBoard
//
//  配置模型 + Application Support 持久化。
//
//  Schema 与 Python v0.1 的 config.json 兼容（键名/字段一致），便于首启迁移。
//  详见 .trellis/spec/backend/directory-structure.md 的 schema 描述。
//
//  并发：actor 隔离，对齐 Python spec 的 CONFIG_LOCK 语义——
//  串口监听线程（阶段 B）读 config、Settings UI（阶段 D）写 config，
//  都经 ConfigStore actor 串行化，避免数据竞争。
//

import Foundation

// MARK: - 配置 schema

/// 单个按键映射。
///
/// 字段含义（对齐 Python spec）：
/// - type: "cmd"（shell 命令）| "key"（击键）| "text"（输入文本）
/// - value:
///   - cmd: shell 字符串（如 "open -a Codex"）
///   - key: 含可选 modifier 的描述（如 "option+d" / "ctrl+c" / "esc" / "enter" / 单字符）
///   - text: 要输入的文本（中文等任意字符）
/// - mode: "tap"（瞬时，osascript/CGEvent 单发）| "hold"（按住，CGEvent）。仅 key 类型有效
/// - enter: 仅 text 类型，粘贴后是否补一个回车（默认 true）
/// - desc: 纯展示用
struct KeyConfig: Codable, Equatable {
    var type: String
    var value: String
    var mode: String?
    var enter: Bool?
    var desc: String?
}

/// 顶层配置：按钮名（如 "k1"）-> KeyConfig。
typealias Config = [String: KeyConfig]

// MARK: - 默认配置

/// 首启默认配置。
///
/// 移植 Python v0.1 config.json 的 4 个键（仓库根 config.json）。
/// 阶段 C 后随 CGEvent/keycode 实现成熟再对齐细节（如 k4 的 hold modifier flags）。
private let defaultConfig: Config = [
    "k1": KeyConfig(type: "cmd",  value: "open -a Codex", mode: "tap",  enter: nil, desc: "打开 Codex"),
    "k2": KeyConfig(type: "text", value: "继续",           mode: nil,   enter: true, desc: "输入'继续'并回车"),
    "k3": KeyConfig(type: "key",  value: "ctrl+c",         mode: "tap",  enter: nil, desc: "Ctrl+C"),
    "k4": KeyConfig(type: "key",  value: "option+d",       mode: "hold", enter: nil, desc: "语音(按住)")
]

// MARK: - 持久化路径

/// 配置文件：~/Library/Application Support/VibeBoard/config.json
private let configURL: URL = {
    let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
        ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    let dir = appSupport.appendingPathComponent("VibeBoard", isDirectory: true)
    return dir.appendingPathComponent("config.json")
}()

// MARK: - 配置存储（actor 串行化）

/// 配置存储：加载/读取/保存串行化，对齐 Python spec 的 CONFIG_LOCK 语义。
///
/// 用法：
///   let cfg = await ConfigStore.shared.load()   // 启动加载或首启写默认
///   let cfg = await ConfigStore.shared.snapshot() // 读快照（拷贝）
///   await ConfigStore.shared.save(newCfg)       // 持久化 + 内存更新
actor ConfigStore {
    /// App 全局单例。串口监听线程（阶段 B）与 Settings UI（阶段 D）共用同一 actor 实例，
    /// 经 actor 串行化保证读写不竞争。
    static let shared = ConfigStore()

    private var config: Config = [:]
    private var didLoad = false

    /// 加载或首启写默认。返回加载后的配置快照。
    /// 幂等：多次调用只有第一次真正读盘/写默认。
    func load() -> Config {
        if didLoad { return config }
        didLoad = true
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
            return config
        }
        // 首启：写默认配置到磁盘
        config = defaultConfig
        persist()
        return config
    }

    /// 返回当前配置的拷贝（actor 隔离下，调用方持有的是不可变快照）。
    func snapshot() -> Config {
        return config
    }

    /// 保存新配置：原子写盘 + 更新内存。
    func save(_ newConfig: Config) {
        config = newConfig
        persist()
    }

    /// 原子落盘：先确保目录存在，再 .atomic 写。
    /// ensure_ascii=false / indent=2 对齐 Python json.dump(..., ensure_ascii=False, indent=2)。
    private func persist() {
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // pretty ≈ indent=2；sortedKeys 让 git diff 稳定
        guard let data = try? encoder.encode(config) else { return }

        // FileManager.atomic 等价于 Python 的临时文件 + rename，避免半写状态。
        try? data.write(to: configURL, options: [.atomic])
    }
}

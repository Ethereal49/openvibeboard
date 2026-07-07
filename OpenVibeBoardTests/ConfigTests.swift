//
//  ConfigTests.swift
//  OpenVibeBoardTests
//
//  阶段 F：Config schema + 默认配置 + ConfigStore 持久化测试。
//
//  - KeyConfig/Config Codable 往返：守护与 Python config.json schema 的兼容
//  - defaultConfig：守护 Python 迁移意图（4 个键 k1-k4 + 各自 type/value/mode）
//  - ConfigStore（注入 URL）：load 首启写默认 / save 原子写读回 / load 幂等 / snapshot 拷贝
//

import Testing
import Foundation
@testable import OpenVibeBoard

@Suite("Config Codable + 默认配置")
enum ConfigSchemaTests {

    // MARK: - KeyConfig Codable 往返（含字段缺省对称性）

    @Test("KeyConfig 完整字段往返")
    static func keyConfigRoundTripFull() throws {
        let original = KeyConfig(type: "key", value: "ctrl+c", mode: "tap", enter: nil, desc: "Ctrl+C")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("KeyConfig 字段缺省（mode/enter/desc 为 nil）往返对称")
    static func keyConfigRoundTripSparse() throws {
        // 对齐 Python schema：mode/enter/desc 可缺省
        let original = KeyConfig(type: "text", value: "继续", mode: nil, enter: nil, desc: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("Config（字典）往返")
    static func configRoundTrip() throws {
        let original: Config = [
            "k1": KeyConfig(type: "cmd", value: "open -a X", mode: "tap", enter: nil, desc: nil),
            "k3": KeyConfig(type: "key", value: "esc", mode: "tap", enter: nil, desc: nil),
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - 默认配置（守护 Python 迁移意图）

    @Test("defaultConfig 含 k1-k4 且字段正确")
    static func defaultConfigShape() throws {
        // 守护：4 个键必须存在（迁移 Python v0.1 config.json）
        #expect(defaultConfig["k1"] != nil)
        #expect(defaultConfig["k2"] != nil)
        #expect(defaultConfig["k3"] != nil)
        #expect(defaultConfig["k4"] != nil)
        #expect(defaultConfig.count == 4)

        // k1: cmd / open -a Codex / tap
        let k1 = try #require(defaultConfig["k1"])
        #expect(k1.type == "cmd")
        #expect(k1.value == "open -a Codex")
        #expect(k1.mode == "tap")

        // k2: text / 继续 / enter=true
        let k2 = try #require(defaultConfig["k2"])
        #expect(k2.type == "text")
        #expect(k2.value == "继续")
        #expect(k2.enter == true)

        // k3: key / ctrl+c / tap
        let k3 = try #require(defaultConfig["k3"])
        #expect(k3.type == "key")
        #expect(k3.value == "ctrl+c")
        #expect(k3.mode == "tap")

        // k4: key / option+d / hold（CGEvent flags 坑的核心 case）
        let k4 = try #require(defaultConfig["k4"])
        #expect(k4.type == "key")
        #expect(k4.value == "option+d")
        #expect(k4.mode == "hold")
    }
}

@Suite("ConfigStore（注入 URL）")
enum ConfigStoreTests {

    /// 临时目录里的 config.json URL，每个测试独立隔离。
    private static func makeURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenVibeBoardTests-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }

    @Test("load 首启：文件不存在则写默认配置到磁盘")
    static func loadWritesDefaultOnFirstLaunch() async throws {
        let url = makeURL()
        let store = ConfigStore(url: url)

        let cfg = await store.load()

        // 内存返回默认
        #expect(cfg.count == 4)
        #expect(cfg["k1"]?.type == "cmd")

        // 落盘：文件存在且能解码回默认
        #expect(FileManager.default.fileExists(atPath: url.path))
        let data = try #require(try? Data(contentsOf: url))
        let decoded = try #require(try? JSONDecoder().decode(Config.self, from: data))
        #expect(decoded.count == 4)
        #expect(decoded["k4"]?.mode == "hold")
    }

    @Test("save：原子写盘 + 读回一致")
    static func saveAtomicRoundTrip() async {
        let url = makeURL()
        let store = ConfigStore(url: url)

        let custom: Config = [
            "kx": KeyConfig(type: "cmd", value: "echo hi", mode: nil, enter: nil, desc: nil),
        ]
        await store.save(custom)

        // 内存 snapshot 一致
        let snap = await store.snapshot()
        #expect(snap["kx"]?.value == "echo hi")

        // 落盘一致（独立 store 读同一 URL 验证原子写）
        let store2 = ConfigStore(url: url)
        let loaded = await store2.load()
        #expect(loaded["kx"]?.value == "echo hi")
    }

    @Test("load 幂等：多次调用只读一次盘")
    static func loadIsIdempotent() async {
        let url = makeURL()
        let store = ConfigStore(url: url)

        // 第一次：首启写默认
        let first = await store.load()
        #expect(first.count == 4)

        // 模拟磁盘被外部清空（首启写完后）
        try? FileManager.default.removeItem(at: url)

        // 第二次：didLoad=true，应返回内存里的 config，不重新读盘（盘已空也不影响）
        let second = await store.load()
        #expect(second.count == 4)
        #expect(second["k1"]?.type == "cmd")
    }

    @Test("snapshot 返回拷贝：外部修改不影响 store 内部")
    static func snapshotReturnsCopy() async {
        let url = makeURL()
        let store = ConfigStore(url: url)
        _ = await store.load()

        var snap = await store.snapshot()
        snap["hacked"] = KeyConfig(type: "cmd", value: "rm -rf /", mode: nil, enter: nil, desc: nil)

        // 再次 snapshot：原 store 不受影响（拷贝语义）
        let snap2 = await store.snapshot()
        #expect(snap2["hacked"] == nil)
        #expect(snap2.count == 4)
    }
}
